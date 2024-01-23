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

            TEXTURE2D(_MainTex);
            SAMPLER(sampler_MainTex);

            float _Intensity;

            half4 frag(Varyings input):SV_Target
            {
                UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(input);
                float2 uv = input.positionCS.xy / float2(1920, 1080);
                float4 color = _SSR_ColorTexture.SampleLevel(sampler_SSR_ColorTexture, uv, 0);
                return color * float4(1, 1, 1, 1);
                // return float4(uv, 0, 1);

            }
            ENDHLSL
        }
    }
}