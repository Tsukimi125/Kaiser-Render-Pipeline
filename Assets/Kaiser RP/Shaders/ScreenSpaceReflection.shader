Shader "Hidden/KaiserRP/ScreenSpaceReflection"
{
    SubShader
    {
        Tags { "RenderType" = "Opaque" "RenderPipeline" = "UniversalPipeline" }
        LOD 100
        ZWrite Off Cull Off
        Pass
        {
            Name "ScreenSpaceReflectionPass"

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

            TEXTURE2D_X(_SSR_PrevTexture);
            SAMPLER(sampler_SSR_PrevTexture);

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
            float _SSR_TemporalWeight;

            float4 _SSR_Resolution;
            
            float4 frag(Varyings input):SV_Target
            {
                UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(input);
                float2 uv = input.positionCS.xy * _SSR_Resolution.zw;
                uint2 pixelPosition = input.positionCS.xy;
                
                float depth = SAMPLE_TEXTURE2D_LOD(_CameraDepthTexture, sampler_linear_clamp, uv, 0).r;

                [branch]
                if (depth <= 1e-4)
                {
                    return 0;
                }

                float3 prevColor = _SSR_PrevTexture.SampleLevel(sampler_SSR_PrevTexture, uv, 0).rgb;

                float4 gbuffer2 = _GBuffer2.SampleLevel(sampler_linear_clamp, uv, 0);
                half roughness = clamp(1.0 - gbuffer2.w, 0.02, 1.0);
                half metallic = _GBuffer1.SampleLevel(sampler_linear_clamp, uv, 0).r;

                // roughness = roughness * roughness;

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
                    roughness = roughness * 7;
                    
                    half4 encodedIrradiance = half4(SAMPLE_TEXTURECUBE_LOD(_GlossyEnvironmentCubeMap, sampler_GlossyEnvironmentCubeMap, reflectionDirWS, 0));
                    sceneColor = DecodeHDREnvironment(encodedIrradiance, _GlossyEnvironmentColor);
                    // half4 encodedIrradiance = half4(SAMPLE_TEXTURECUBE_LOD(unity_SpecCube0, samplerunity_SpecCube0, reflectionDirWS, 1));
                    // sceneColor = DecodeHDREnvironment(encodedIrradiance, unity_SpecCube0_HDR);
                    // return float4(sceneColor, 1.0f);// F0 * sceneColor * hitSuccessful.xxx

                }
                // brdf and pdf ?
                // return 0;
                return float4(lerp(saturate(F0 * sceneColor), prevColor, _SSR_TemporalWeight), 1.0);// F0 * sceneColor * hitSuccessful.xxx

            }
            ENDHLSL
        }
        Pass
        {
            Name "ScreenSpaceReflectionDenoisePass"

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

            TEXTURE2D_X(_MainTex);
            SAMPLER(sampler_MainTex);

            TEXTURE2D_X(_CameraOpaqueTexture);
            SAMPLER(sampler_CameraOpaqueTexture);

            TEXTURE2D_X(_SSR_ColorTexture);
            SAMPLER(sampler_SSR_ColorTexture);

            TEXTURE2D_X(_SSR_PrevTexture);
            SAMPLER(sampler_SSR_PrevTexture);

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
            float _SSR_TemporalWeight;

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

                float3 prevColor = _SSR_PrevTexture.SampleLevel(sampler_SSR_PrevTexture, uv, 0).rgb;

                float4 gbuffer2 = _GBuffer2.SampleLevel(sampler_linear_clamp, uv, 0);
                half roughness = clamp(1.0 - gbuffer2.w, 0.02, 1.0);
                half metallic = _GBuffer1.SampleLevel(sampler_linear_clamp, uv, 0).r;

                // roughness = roughness * roughness;

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

                float3 color = _MainTex.Sample(sampler_MainTex, uv).rgb;
                
                return float4(color, 1.0f);
            }
            ENDHLSL
        }
    }
}