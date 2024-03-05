Shader "Hidden/KaiserRP/ScreenSpaceGlobalIllumination"
{
    SubShader
    {
        Tags { "RenderType" = "Opaque" "RenderPipeline" = "UniversalPipeline" }
        LOD 100
        ZWrite Off Cull Off
        Pass
        {
            Name "ScreenSpaceGlobalIlluminationPass"

            HLSLPROGRAM
            
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Common.hlsl"
            #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/SpaceTransforms.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/Shaders/Utils/Deferred.hlsl"
            // The Blit.hlsl file provides the vertex shader (Vert),
            // input structure (Attributes) and output strucutre (Varyings)
            #include "Packages/com.unity.render-pipelines.core/Runtime/Utilities/Blit.hlsl"
            #include "../ShaderLibrary/RandomFunctions.hlsl"
            #include "../ShaderLibrary/SamplingFunctions.hlsl"
            #include "../ShaderLibrary/KaiserSpaceTransformFunctions.hlsl"
            #include "../ShaderLibrary/KaiserScreenSpaceRayTracing.hlsl"
            #pragma vertex Vert
            #pragma fragment frag

            TEXTURE2D_X(_CameraOpaqueTexture);
            SAMPLER(sampler_CameraOpaqueTexture);

            TEXTURE2D_X(_SSR_ColorTexture);
            SAMPLER(sampler_SSR_ColorTexture);

            TEXTURE2D_X(_GBuffer0);
            SAMPLER(sampler_GBuffer0);

            TEXTURE2D_X(_GBuffer1);
            SAMPLER(sampler_GBuffer1);

            TEXTURE2D_X(_GBuffer2);
            SAMPLER(sampler_GBuffer2);

            TEXTURE2D(_CameraDepthTexture);
            SAMPLER(sampler_CameraDepthTexture);

            SAMPLER(sampler_linear_clamp);

            float _Intensity;
            float _SSR_FrameIndex;

            float4 frag(Varyings input):SV_Target
            {
                UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(input);
                float2 uv = input.positionCS.xy / float2(1920, 1080);
                uint2 pixelPosition = input.positionCS.xy;
                
                float depth = SAMPLE_TEXTURE2D_LOD(_CameraDepthTexture, sampler_linear_clamp, uv, 0).r;

                [branch]
                if (depth <= 1e-4)
                {
                    return 0;
                }

                float4 gbuffer2 = _GBuffer2.SampleLevel(sampler_linear_clamp, uv, 0);
                half roughness = clamp(1.0 - gbuffer2.w, 0.02, 1.0);
                half metallic = _GBuffer1.SampleLevel(sampler_linear_clamp, uv, 0).r;

                roughness = roughness * roughness;

                // Compute F0
                half3 F0 = 0.04f.xxx;
                half3 albedo = _GBuffer0.SampleLevel(sampler_linear_clamp, uv, 0).rgb;
                F0 = lerp(F0, albedo, metallic);
                // F0 = lerp(F0, 1.0f.xxx, 0);
                
                float3 worldNormal = UnpackNormal(gbuffer2);
                worldNormal = gbuffer2.xyz;
                float3 viewNormal = TransformWorldToViewNormal(worldNormal);
                float4 NDCPos = ComputeClipSpacePosition(uv, depth);
                float3 worldPos = ComputeWorldSpacePosition(uv, depth, UNITY_MATRIX_I_VP);
                float3 viewPos = ComputeViewSpacePosition(uv, depth, UNITY_MATRIX_I_P);
                viewPos.z = -viewPos.z;

                // rand gen
                uint frameIDMod8 = uint(fmod(_SSR_FrameIndex, 1024));
                uint2 random = Rand3DPCG16(uint3(pixelPosition, frameIDMod8)).xy;
                float2 hash = frac(Hammersley16(frameIDMod8, (uint)1024, random));

                float4 H = float4(worldNormal, 1.0);
                H = TangentToWorld(ImportanceSampleGGX(hash, roughness).xyz, float4(worldNormal, 1.0));
                float3 reflectionDirWS = reflect(normalize(worldPos - _WorldSpaceCameraPos), H.xyz);
                
                Ray ray;
                ray.pos = worldPos;
                ray.dir = reflectionDirWS;
                float2 hitUV;
                bool hitSuccessful;

                LinearTrace(ray, _CameraDepthTexture, sampler_linear_clamp, random, hitSuccessful, hitUV);

                float3 sceneColor = _SSR_ColorTexture.SampleLevel(sampler_SSR_ColorTexture, hitUV, 0).rgb;
                if (!hitSuccessful)
                {
                    half4 encodedIrradiance = half4(SAMPLE_TEXTURECUBE_LOD(unity_SpecCube0, samplerunity_SpecCube0, reflectionDirWS, 0));
                    sceneColor = DecodeHDREnvironment(encodedIrradiance, unity_SpecCube0_HDR);
                    return float4(encodedIrradiance);// F0 * sceneColor * hitSuccessful.xxx
                }
                // brdf and pdf ?
                // return 0;
                return float4(saturate(F0 * sceneColor), 1.0);// F0 * sceneColor * hitSuccessful.xxx
                // return float4(worldNormal, 1.0f) * float4(1, 1, 1, 1);
                // return float4(uv, 0, 1);

            }
            ENDHLSL
        }
    }
}