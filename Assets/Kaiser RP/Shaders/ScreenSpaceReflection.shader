Shader "Hidden/KaiserRP/ScreenSpaceReflection"
{
    SubShader
    {
        Tags { "RenderType" = "Opaque" "RenderPipeline" = "UniversalPipeline" }
        LOD 100
        ZWrite Off Cull Off
        HLSLINCLUDE
        #pragma shader_feature KAISER_SSGI
        ENDHLSL
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


                float3 prevColor = _SSR_PrevTexture.SampleLevel(sampler_SSR_PrevTexture, uv, 0).rgb;

                float4 gbuffer2 = _GBuffer2.SampleLevel(sampler_linear_clamp, uv, 0);
                half roughness = clamp(1.0 - gbuffer2.w, 0.001f, 1.0);
                
                
                [branch]
                if (depth <= 1e-4) //  || roughness > 0.5

                {
                    return 0;
                }
                
                half metallic = _GBuffer1.SampleLevel(sampler_linear_clamp, uv, 0).r;
                #ifdef KAISER_SSGI
                    roughness = 0.99f;
                    metallic = 0.01f;
                #endif
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
                uint frameIDMod8 = uint(fmod(_SSR_FrameIndex, 8192));
                uint2 random = Rand3DPCG16(uint3(pixelPosition, frameIDMod8)).xy;
                float2 hash = frac(Hammersley16(frameIDMod8, (uint)8192, random));
                
                float3 reflectionDirWS;
                
                #ifdef KAISER_SSGI
                    reflectionDirWS = TangentToWorld(ImportanceSampleGGX(hash, roughness).xyz, float4(worldNormal, 1.0));
                #else
                    float4 H = float4(worldNormal, 1.0);
                    H = TangentToWorld(ImportanceSampleGGX(hash, roughness).xyz, float4(worldNormal, 1.0));
                    reflectionDirWS = reflect(normalize(worldPos - _WorldSpaceCameraPos), H.xyz);
                #endif
                
                Ray ray;
                ray.pos = worldPos;
                ray.dir = reflectionDirWS;
                float2 hitUV;
                bool hitSuccessful;

                LinearTrace(ray, _CameraDepthTexture, sampler_linear_clamp, random, hitSuccessful, hitUV);

                float3 sceneColor = _SSR_ColorTexture.SampleLevel(sampler_SSR_ColorTexture, hitUV, 0).rgb * 1.25f;
                if (!hitSuccessful)
                {
                    half4 encodedIrradiance = half4(SAMPLE_TEXTURECUBE_LOD(_GlossyEnvironmentCubeMap, sampler_GlossyEnvironmentCubeMap, reflectionDirWS, 0));
                    sceneColor = DecodeHDREnvironment(encodedIrradiance, _GlossyEnvironmentColor) * 1.0;
                    // sceneColor = 0;
                    // half4 encodedIrradiance = half4(SAMPLE_TEXTURECUBE_LOD(unity_SpecCube0, samplerunity_SpecCube0, reflectionDirWS, 1));
                    // sceneColor = DecodeHDREnvironment(encodedIrradiance, unity_SpecCube0_HDR);
                    // return float4(sceneColor, 1.0f);// F0 * sceneColor * hitSuccessful.xxx

                }
                // brdf and pdf ?
                // return 0;
                // return float4(lerp(saturate(sceneColor), prevColor, _SSR_TemporalWeight), 1.0);// F0 * sceneColor * hitSuccessful.xxx
                #ifdef KAISER_SSGI
                    return float4(lerp(clamp(sceneColor, 0, 10.0f), prevColor, _SSR_TemporalWeight), 1.0);
                #endif

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
            float _SSR_DenoiseKernelSize;

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
                #ifdef KAISER_SSGI
                    roughness = 1.0f;
                    metallic = 0.0f;
                #endif
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
                
                const float2 offset[25] = {

                    {
                        - 2, -2
                    },
                    {
                        - 1, -2
                    },
                    {
                        0, -2
                    },
                    {
                        1, -2
                    },
                    {
                        2, -2
                    },
                    {
                        - 2, -1
                    },
                    {
                        - 1, -1
                    },
                    {
                        0, -1
                    },
                    {
                        1, -1
                    },
                    {
                        2, -1
                    },
                    {
                        - 2, 0
                    },
                    {
                        - 1, 0
                    },
                    {
                        0, 0
                    },
                    {
                        1, 0
                    },
                    {
                        2, 0
                    },
                    {
                        - 2, 1
                    },
                    {
                        - 1, 1
                    },
                    {
                        0, 1
                    },
                    {
                        1, 1
                    },
                    {
                        2, 1
                    },
                    {
                        - 2, 2
                    },
                    {
                        - 1, 2
                    },
                    {
                        0, 2
                    },
                    {
                        1, 2
                    },
                    {
                        2, 2
                    }
                };
                
                float3 sceneColor = _SSR_ColorTexture.SampleLevel(sampler_linear_clamp, uv, 0).rgb;

                float3 centerColor = _BlitTexture.SampleLevel(sampler_linear_clamp, uv, 0).rgb;
                float3 centerNormal = UnpackNormal(_GBuffer2.SampleLevel(sampler_linear_clamp, uv, 0).rgb);
                float3 centerWorldPos = ComputeWorldSpacePosition(uv, depth, UNITY_MATRIX_I_VP).xyz;
                
                // float colorPhi = 1.0f / 3.3f;
                // float normalPhi = 0.01f / 2.0f ;
                // float worldPosPhi = 0.5f / 5.5f;
                float factor = 2.0f;
                float colorPhi = 0.303f * factor;
                float normalPhi = 0.005f * factor;
                float worldPosPhi = 0.091f * factor;

                float3 finalColor = float3(0.0, 0.0, 0.0);
                float weight = 0.0;
                float weightSum = 0.0;

                for (int i = 0; i < 25; i++)
                {
                    float2 offsetUV = uv + offset[i] * _SSR_Resolution.zw * _SSR_DenoiseKernelSize * (roughness + 0.1);
                    float3 offsetColor = _BlitTexture.SampleLevel(sampler_linear_clamp, offsetUV, 0).rgb;
                    float3 t = centerColor - offsetColor;
                    float colorWeight = min(exp(-dot(t, t) * colorPhi), 1.0);

                    float3 offsetNormal = UnpackNormal(_GBuffer2.SampleLevel(sampler_linear_clamp, offsetUV, 0).rgb);
                    t = centerNormal - offsetNormal;
                    float normalWeight = min(exp(-dot(t, t) * normalPhi), 1.0);

                    float3 offsetWorldPos = ComputeWorldSpacePosition(offsetUV, depth, UNITY_MATRIX_I_VP).xyz;
                    t = centerWorldPos - offsetWorldPos;
                    float worldPosWeight = min(exp(-dot(t, t) * worldPosPhi), 1.0);

                    weight = colorWeight * normalWeight * worldPosWeight;
                    finalColor += offsetColor * weight;
                    weightSum += weight;
                }
                
                return float4(finalColor / weightSum, 1.0f);
            }
            ENDHLSL
        }
        Pass
        {
            Name "ScreenSpaceReflectionDenoiseCombinePass"

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
            float _SSR_DenoiseKernelSize;

            float4 _SSR_Resolution;

            float4 frag(Varyings input):SV_Target
            {
                UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(input);
                float2 uv = input.positionCS.xy * _SSR_Resolution.zw;
                uint2 pixelPosition = input.positionCS.xy;
                
                float depth = SAMPLE_TEXTURE2D_LOD(_CameraDepthTexture, sampler_linear_clamp, uv, 0).r;
                
                float3 sceneColor = _SSR_ColorTexture.SampleLevel(sampler_linear_clamp, uv, 0).rgb;

                

                float3 prevColor = _SSR_PrevTexture.SampleLevel(sampler_SSR_PrevTexture, uv, 0).rgb;

                float4 gbuffer2 = _GBuffer2.SampleLevel(sampler_linear_clamp, uv, 0);
                half roughness = clamp(1.0 - gbuffer2.w, 0.001f, 1.0);
                half metallic = _GBuffer1.SampleLevel(sampler_linear_clamp, uv, 0).r;

                #ifdef KAISER_SSGI
                    roughness = 1.0f;
                    metallic = 0.0f;
                #endif

                [branch]
                if (depth <= 1e-4) // || roughness > 0.49)

                {
                    return float4(sceneColor, 1.0f);
                }
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
                
                const float2 offset[25] = {

                    {
                        - 2, -2
                    },
                    {
                        - 1, -2
                    },
                    {
                        0, -2
                    },
                    {
                        1, -2
                    },
                    {
                        2, -2
                    },
                    {
                        - 2, -1
                    },
                    {
                        - 1, -1
                    },
                    {
                        0, -1
                    },
                    {
                        1, -1
                    },
                    {
                        2, -1
                    },
                    {
                        - 2, 0
                    },
                    {
                        - 1, 0
                    },
                    {
                        0, 0
                    },
                    {
                        1, 0
                    },
                    {
                        2, 0
                    },
                    {
                        - 2, 1
                    },
                    {
                        - 1, 1
                    },
                    {
                        0, 1
                    },
                    {
                        1, 1
                    },
                    {
                        2, 1
                    },
                    {
                        - 2, 2
                    },
                    {
                        - 1, 2
                    },
                    {
                        0, 2
                    },
                    {
                        1, 2
                    },
                    {
                        2, 2
                    }
                };
                

                float3 centerColor = _BlitTexture.SampleLevel(sampler_linear_clamp, uv, 0).rgb;
                float3 centerNormal = UnpackNormal(_GBuffer2.SampleLevel(sampler_linear_clamp, uv, 0).rgb);
                float3 centerWorldPos = ComputeWorldSpacePosition(uv, depth, UNITY_MATRIX_I_VP).xyz;
                
                // float colorPhi = 1.0f / 3.3f;
                // float normalPhi = 0.01f / 2.0f ;
                // float worldPosPhi = 0.5f / 5.5f;
                float factor = 2.0f;
                float colorPhi = 0.303f * factor;
                float normalPhi = 0.005f * factor;
                float worldPosPhi = 0.091f * factor;

                float3 finalColor = float3(0.0, 0.0, 0.0);
                float weight = 0.0;
                float weightSum = 0.0;

                for (int i = 0; i < 25; i++)
                {
                    float2 offsetUV = uv + offset[i] * _SSR_Resolution.zw * _SSR_DenoiseKernelSize * (roughness + 0.08);
                    float3 offsetColor = _BlitTexture.SampleLevel(sampler_linear_clamp, offsetUV, 0).rgb;
                    float3 t = centerColor - offsetColor;
                    float colorWeight = min(exp(-dot(t, t) * colorPhi), 1.0);

                    float3 offsetNormal = UnpackNormal(_GBuffer2.SampleLevel(sampler_linear_clamp, offsetUV, 0).rgb);
                    t = centerNormal - offsetNormal;
                    float normalWeight = min(exp(-dot(t, t) * normalPhi), 1.0);

                    float3 offsetWorldPos = ComputeWorldSpacePosition(offsetUV, depth, UNITY_MATRIX_I_VP).xyz;
                    t = centerWorldPos - offsetWorldPos;
                    float worldPosWeight = min(exp(-dot(t, t) * worldPosPhi), 1.0);

                    weight = colorWeight * normalWeight * worldPosWeight;
                    finalColor += offsetColor * weight;
                    weightSum += weight;
                }
                return float4(sceneColor + finalColor * _Intensity / weightSum, 1.0f); // sceneColor +

            }
            ENDHLSL
        }
    }
}