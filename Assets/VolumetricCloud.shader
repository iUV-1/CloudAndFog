Shader "Custom/VolumetricCloud"
{
    Properties
    {
        _Color("Fog Color", Color) = (0.7,0.7,0.8,1)
        _StepSize("Step Size", Range(0.01, 1)) = 0.06
        _Density("Density", Range(0,10)) = 2.5
        _FogNoise("Fog Noise", 3D) = "white" {}
        _NoiseScale("Noise Scale", Float) = 1.5

        _DensityThreshold("Density Threshold", Range(0,1)) = 0.08
        _DensityMultiplier("Density Multiplier", Range(0,10)) = 2.0

        [HDR]_lightContribution("Light Contribution", Color) = (1,1,1,1)
        _LightScattering("Light Scattering", Range(-0.95,0.95)) = 0.2
        
        [Header(Self Shadowing)]
        _LightSteps("Light Ray Steps", Range(1, 10)) = 4
        _LightStepMultiplier("Light Step Multiplier", Range(1, 10)) = 3.0
        _ShadowDensity("Shadow Density", Range(0, 5)) = 1.0
    }

    SubShader
    {
        Tags { "RenderType" = "Transparent" "Queue" = "Transparent" }

        Pass
        {
            Blend SrcAlpha OneMinusSrcAlpha
            ZWrite Off
            Cull Front 
            ZTest Always

            HLSLPROGRAM
            #pragma vertex Vert
            #pragma fragment Frag
            #pragma target 3.0

            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE _MAIN_LIGHT_SHADOWS_SCREEN
            
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            float4 _Color;
            float _StepSize;
            float _Density;
            TEXTURE3D(_FogNoise);
            float _NoiseScale;
            float _DensityThreshold;
            float _DensityMultiplier;
            float4 _lightContribution;
            float _LightScattering;
            
            // New shadow properties
            int _LightSteps;
            float _LightStepMultiplier;
            float _ShadowDensity;

            static const float P = 3.141;
            static const float EPS = 1e-6;

            struct a2v
            {
                float4 positionOS : POSITION;
            };

            struct v2f
            {
                float4 positionHCS : SV_POSITION;
                float3 worldPos    : TEXCOORD0;
            };

            v2f Vert(a2v IN)
            {
                v2f OUT;
                OUT.positionHCS = TransformObjectToHClip(IN.positionOS);
                OUT.worldPos = TransformObjectToWorld(IN.positionOS.xyz);
                return OUT;
            }

            float henyey_greenstein(float cosTheta, float g)
            {
                float denom = 1.0 + g*g - 2.0*g*cosTheta;
                denom = max(denom, 1e-6);
                return (1.0 - g*g) / (4.0 * PI * pow(denom, 1.5));
            }

            float get_density(float3 localPos)
            {
                float3 uvw = localPos + 0.5; 
                float4 n = _FogNoise.SampleLevel(sampler_TrilinearClamp, uvw.xzy * _NoiseScale, 0);
                float noiseVal = dot(n, n);
                float density = saturate(noiseVal - _DensityThreshold) * _DensityMultiplier * _Density;
                return density;
            }

            bool RayBoxIntersection(float3 rayOrigin, float3 rayDir, float3 boxMin, float3 boxMax, out float tmin, out float tmax)
            {
                float3 invDir = 1.0 / rayDir; 
                float3 t0 = (boxMin - rayOrigin) * invDir;
                float3 t1 = (boxMax - rayOrigin) * invDir;

                float3 tmin3 = min(t0, t1);
                float3 tmax3 = max(t0, t1);

                tmin = max(max(tmin3.x, tmin3.y), tmin3.z);
                tmax = min(min(tmax3.x, tmax3.y), tmax3.z);

                return tmax >= max(tmin, 0.0);
            }

            half4 Frag(v2f IN) : SV_Target
            {
                float3 camWS = _WorldSpaceCameraPos;
                float3 viewDirWS = normalize(IN.worldPos - camWS);

                float3 localOrigin = TransformWorldToObject(camWS);
                float3 localDir = mul((float3x3)unity_WorldToObject, viewDirWS);
                localDir = normalize(localDir);

                float3 boxMin = float3(-0.5, -0.5, -0.5);
                float3 boxMax = float3( 0.5,  0.5,  0.5);

                float t0, t1;
                
                if (!RayBoxIntersection(localOrigin, localDir, boxMin, boxMax, t0, t1))
                {
                    return float4(0,0,0,0);
                }

                t0 = max(t0, 0.0);
                float maxLen = t1 - t0;
                if (maxLen <= 0) return float4(0,0,0,0);

                int steps = (int)ceil(maxLen / max(_StepSize, 1e-6));
                steps = min(steps, 1024);

                float transmittance = 1.0;
                float3 accumulatedScattering = float3(0,0,0);

                Light globalMainLight = GetMainLight();
                float3 lightDirWS = normalize(globalMainLight.direction);
                float3 baseLightColor = globalMainLight.color * _lightContribution.rgb;

                // Transform light direction to local space so we can raymarch the 3D noise efficiently
                float3 lightDirLocal = mul((float3x3)unity_WorldToObject, lightDirWS);
                lightDirLocal = normalize(lightDirLocal);

                // Raymarch
                for (int i = InterleavedGradientNoise(IN.positionHCS, (int)(_Time.y / max(HALF_EPS, unity_DeltaTime.x))); i < steps; ++i)
                {
                    float t = t0 + (i + 0.5) * _StepSize; 
                    if (t > t1) break;

                    float3 localPos = localOrigin + localDir * t; 
                    float density = get_density(localPos);

                    if (density > 0)
                    {
                        // --- SECONDARY RAYMARCH (SELF-SHADOWING) ---
                        float shadowDensity = 0;
                        float3 shadowPosLocal = localPos;
                        float lightStepDist = _StepSize * _LightStepMultiplier;

                        for (int j = 0; j < _LightSteps; j++)
                        {
                            shadowPosLocal += lightDirLocal * lightStepDist;
                            
                            // Prevent sampling noise outside the cube bounds
                            if (abs(shadowPosLocal.x) > 0.5 || abs(shadowPosLocal.y) > 0.5 || abs(shadowPosLocal.z) > 0.5) 
                                break;

                            shadowDensity += get_density(shadowPosLocal);
                        }

                        // Beer's Law for the light ray
                        float lightTransmittance = exp(-shadowDensity * lightStepDist * _ShadowDensity);
                        // -------------------------------------------

                        float3 samplePosWS = TransformObjectToWorld(localPos);
                        float cosTheta = dot(-viewDirWS, lightDirWS); 
                        float phase = henyey_greenstein(cosTheta, clamp(_LightScattering, -0.95, 0.95));

                        float4 shadowCoord = TransformWorldToShadowCoord(samplePosWS);
                        Light stepLight = GetMainLight(shadowCoord);
                        
                        // Multiply inscatter by our new lightTransmittance
                        float3 inscatter = baseLightColor * phase * density * stepLight.shadowAttenuation * lightTransmittance;

                        float atten = transmittance * (1.0 - exp(-density * _StepSize));
                        accumulatedScattering += inscatter * atten;
                        transmittance *= exp(-density * _StepSize);

                        if (transmittance < 0.01) { transmittance = 0.0; break; }
                    }
                }

                float alpha = saturate(1.0 - transmittance);
                float3 finalFog = accumulatedScattering * _Color.rgb;

                return float4(finalFog, alpha);
            }

            ENDHLSL
        }
    }
    FallBack "Diffuse"
}