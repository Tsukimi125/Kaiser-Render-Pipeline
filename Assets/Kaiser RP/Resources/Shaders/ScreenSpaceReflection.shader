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
            // The Blit.hlsl file provides the vertex shader (Vert),
            // input structure (Attributes) and output strucutre (Varyings)
            #include "Packages/com.unity.render-pipelines.core/Runtime/Utilities/Blit.hlsl"

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

            half4 frag(Varyings input):SV_Target
            {
                UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(input);
                float2 uv = input.positionCS.xy / float2(1920, 1080);
                float4 color = _SSR_ColorTexture.SampleLevel(sampler_SSR_ColorTexture, uv, 0);

                float depth = SAMPLE_TEXTURE2D_LOD(_CameraDepthTexture, sampler_linear_clamp, uv, 0).r;

                [branch]
                if (depth <= 1e-4)
                {
                    return 0;
                }

                float4 gbuffer2 = _GBuffer2.SampleLevel(sampler_linear_clamp, uv, 0);
                half roughness = clamp(1.0 - gbuffer2.w, 0.02, 1.0);
                half metallic = _GBuffer1.SampleLevel(sampler_linear_clamp, uv, 0).r;

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

                return float4(worldNormal, 1.0f) * float4(1, 1, 1, 1);
                // return float4(uv, 0, 1);

            }
            ENDHLSL
        }
    }
}