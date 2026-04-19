Shader "Custom/VolumetricFogBox"
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
    }

    SubShader
    {
        // Transparent / rendered after opaque
        Tags { "RenderType" = "Transparent" "Queue" = "Transparent" }

        Pass
        {
            // Use single blend mode: alpha blending (not additive)
            Blend SrcAlpha OneMinusSrcAlpha
            ZWrite Off
            Cull Off
            ZTest LEqual

            HLSLPROGRAM
            #pragma vertex Vert
            #pragma fragment Frag
            #pragma target 3.0

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            // Properties
            float4 _Color;
            float _StepSize;
            float _Density;
            TEXTURE3D(_FogNoise);
            float _NoiseScale;
            float _DensityThreshold;
            float _DensityMultiplier;
            float4 _lightContribution;
            float _LightScattering;

            // small constants
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

            // Henyey-Greenstein phase function (normalized-ish)
            float henyey_greenstein(float cosTheta, float g)
            {
                float denom = 1.0 + g*g - 2.0*g*cosTheta;
                denom = max(denom, 1e-6);
                return (1.0 - g*g) / (4.0 * PI * pow(denom, 1.5));
            }

            // Sample density from the 3D noise
            float get_density(float3 localPos)
            {
                // localPos is in object local space (we treat box spanning [-0.5,0.5])
                // map localPos -> [0..1] for sampling the 3D texture (convention)
                float3 uvw = localPos + 0.5; // now 0..1 over the box
                float4 n = _FogNoise.SampleLevel(sampler_TrilinearRepeat, uvw.xzy * _NoiseScale, 0);
                // combine channels to produce a scalar (keeping it cheap)
                float noiseVal = dot(n, n);
                float density = saturate(noiseVal - _DensityThreshold) * _DensityMultiplier * _Density;
                return density;
            }

            // Ray-box intersection (axis-aligned box min/max in object-local space)
            bool RayBoxIntersection(float3 rayOrigin, float3 rayDir, float3 boxMin, float3 boxMax, out float tmin, out float tmax)
            {
                // slab method
                float3 invDir = 1.0 / max(abs(rayDir), EPS) * sign(rayDir); // avoid divide by zero
                float3 t0 = (boxMin - rayOrigin) / max(rayDir, EPS);
                float3 t1 = (boxMax - rayOrigin) / max(rayDir, EPS);

                float3 tmin3 = min(t0, t1);
                float3 tmax3 = max(t0, t1);

                tmin = max(max(tmin3.x, tmin3.y), tmin3.z);
                tmax = min(min(tmax3.x, tmax3.y), tmax3.z);

                return tmax >= max(tmin, 0.0);
            }

            half4 Frag(v2f IN) : SV_Target
            {
                // Camera position
                float3 camWS = _WorldSpaceCameraPos;

                // Ray from camera to the fragment's world position (surface point)
                float3 viewDirWS = normalize(IN.worldPos - camWS);

                // Transform to object-local space (so box is axis-aligned -0.5..0.5)
                float3 localOrigin = TransformWorldToObject(camWS); // camera origin in object space
                // For direction, transform by the 3x3 (no translation), preserving direction correctly under non-uniform scale:
                float3 localDir = mul((float3x3)unity_WorldToObject, viewDirWS);
                localDir = normalize(localDir);

                // Box bounds (object-space) - default Unity cube uses [-0.5, 0.5]
                float3 boxMin = float3(-0.5, -0.5, -0.5);
                float3 boxMax = float3( 0.5,  0.5,  0.5);

                float t0, t1;
                if (!RayBoxIntersection(localOrigin, localDir, boxMin, boxMax, t0, t1))
                {
                    // Ray does not hit the volume -> no fog contribution
                    return float4(0,0,0,0);
                }

                // Clamp start to zero (don't march behind camera)
                t0 = max(t0, 0.0);

                // Safety: clamp t1 so we don't run forever
                float maxLen = t1 - t0;
                if (maxLen <= 0) return float4(0,0,0,0);

                // Step count (limit to avoid infinite loops)
                int steps = (int)ceil(maxLen / max(_StepSize, 1e-6));
                steps = min(steps, 1024); // safety cap

                // Accumulate scattering and transmittance along ray
                float transmittance = 1.0;
                float3 accumulatedScattering = float3(0,0,0);

                // approximate light direction for scattering: use main directional direction if available
                // To keep it robust across pipelines, use a simple directional guess (sun coming from above)
                float3 lightDirWS = normalize(float3(0.3, 0.75, 0.5)); // tunable but constant fallback
                float3 lightColor = _lightContribution.rgb;

                // Raymarch
                for (int i = InterleavedGradientNoise(IN.positionHCS, (int)(_Time.y / max(HALF_EPS, unity_DeltaTime.x))); i < steps; ++i)
                {
                    float t = t0 + (i + 0.5) * _StepSize; // sample at cell center
                    if (t > t1) break;

                    float3 localPos = localOrigin + localDir * t; // sample position in object local space

                    // density at this sample
                    float density = get_density(localPos);

                    if (density > 0)
                    {
                        // phase term (HG)
                        // compute cosθ between view direction and light direction (use world-space directions)
                        float3 samplePosWS = TransformObjectToWorld(localPos);
                        float3 viewDirSampleWS = normalize(samplePosWS - camWS); // same as viewDirWS but fine
                        float cosTheta = dot(-viewDirSampleWS, lightDirWS); // angle between scattered into view and light direction

                        float phase = henyey_greenstein(cosTheta, clamp(_LightScattering, -0.95, 0.95));

                        // in-scattered radiance at this point (lightColor * phase * density)
                        float3 inscatter = lightColor * phase * density;

                        // accumulate (Beer-Lambert-like)
                        float atten = transmittance * (1.0 - exp(-density * _StepSize));
                        accumulatedScattering += inscatter * atten;

                        // update transmittance
                        transmittance *= exp(-density * _StepSize);

                        // early out if nearly opaque
                        if (transmittance < 0.01) { transmittance = 0.0; break; }
                    }
                }

                // Alpha is amount of light the fog added or amount of extinction (1 - transmittance)
                float alpha = saturate(1.0 - transmittance);

                // final fog color (modulated by main color)
                float3 finalFog = accumulatedScattering * _Color.rgb;

                // return non-premultiplied color + alpha (we use SrcAlpha OneMinusSrcAlpha)
                return float4(finalFog, alpha);
            }

            ENDHLSL
        }
    }
    FallBack "Diffuse"
}
