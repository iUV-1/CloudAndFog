Shader "Custom/VolumetricFog"
{
    Properties
    {
        _Color("Fog Color", Color) = (1,1,1,1)
        _MaxDistance("Max distance", float) = 100
        _StepSize("Step size", Range(0.1, 20)) = 1
        _DensityMultiplier("Density multiplier", Range(0, 1)) = 1
        _NoiseOffset("Noise offset", float) = 1

        _FogNoise("FogNoise", 3D) = "white" { }
        _NoiseTiling("NoiseTiling", float) = 1
        _DensityThreshold("DensityThreshold", Range(0, 1)) = 0.1
        [HDR] _lightContribution("Light Contribution", Color) = (1,1,1,1)
        _LightScattering("Light Scattering", Range(0,1)) = 0.2
        
    }
    SubShader
    {
        Tags { "RenderType"="Opaque"}

        Pass
        {
            HLSLPROGRAM
            #pragma vertex Vert
            #pragma fragment frag
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE _MAIN_LIGHT_SHADOWS_SCREEN
            #pragma multi_compile _ _ADDITIONAL_LIGHT_SHADOWS
            
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
            #include "Packages/com.unity.render-pipelines.core/Runtime/Utilities/Blit.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareDepthTexture.hlsl"

            float _MaxDistance;
            float _DensityMultiplier;
            float _StepSize;
            float _NoiseOffset;
            TEXTURE3D(_FogNoise);
            float _NoiseTiling;
            float _DensityThreshold;
            float4 _lightContribution;
            float4 _Color;
            float _LightScattering;

            float henyey_greenstein(float angle, float scattering)
            {
                return (1.0 - angle * angle) / (4.0 * PI * pow(1.0 + scattering * scattering - (2.0 * scattering) * angle, 1.5f));
            }
            
            float get_density(float3 rayPos)
            {
                float4 noise = _FogNoise.SampleLevel(sampler_TrilinearRepeat, rayPos * 0.01 * _NoiseTiling, 0);
                float density = dot(noise, noise);
                density = saturate(density - _DensityThreshold) * _DensityMultiplier;
                return density;
            }
            
            half4 frag(Varyings IN): SV_Target
            {
                // current color
                float4 col = SAMPLE_TEXTURE2D(_BlitTexture, sampler_LinearClamp, IN.texcoord);
                float depth = SampleSceneDepth(IN.texcoord);
                float3 worldPos = ComputeWorldSpacePosition(IN.texcoord, depth, UNITY_MATRIX_I_VP);

                float3 entryPoint = _WorldSpaceCameraPos;
                float3 viewDir = worldPos - entryPoint;
                float viewLength = length(viewDir);
                float3 rayDir = normalize(viewDir);
                float4 fogCol = float4(0, 0, 0 ,0);

                float2 pixelCoords = IN.texcoord * _BlitTexture_TexelSize.zw;
                
                float distLimit = min(viewLength, _MaxDistance);
                float distTraveled = InterleavedGradientNoise(pixelCoords, (int)(_Time.y / max(HALF_EPS, unity_DeltaTime.x))) * _NoiseOffset;
                float transmittance = 1;

                while (distTraveled < distLimit)
                {
                    float3 rayPos = entryPoint + rayDir * distTraveled;
                    float density = get_density(rayPos);
                    if (density > 0)
                    {
                        Light mainLight = GetMainLight(TransformWorldToShadowCoord(rayPos));
                        float3 litColor = mainLight.color.rgb * _lightContribution.rgb * mainLight.shadowAttenuation;
                        fogCol.rgb += litColor * henyey_greenstein(dot(rayDir, mainLight.direction), _LightScattering) * density * _Color.rgb;
                        transmittance *= exp(-density * _StepSize);
                    }
                    distTraveled += _StepSize;
                }
                return lerp(col, fogCol, 1.0 - saturate(transmittance));
            }
            ENDHLSL
        }
    }
    FallBack "Diffuse"
}
