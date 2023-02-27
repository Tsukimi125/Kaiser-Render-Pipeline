Shader "HBAO"
{
    SubShader
    {
        Tags { "RenderType" = "Opaque" }
        LOD 100

        Cull Off
        ZWrite Off
        ZTest Always

        Pass
        {
            
            Name "HBAO"

            HLSLPROGRAM

            #pragma multi_compile_fragment _ _GBUFFER_NORMALS_OCT
            #pragma multi_compile_local _SOURCE_DEPTH _SOURCE_DEPTH_NORMALS
            #pragma multi_compile_local _RECONSTRUCT_NORMAL_LOW _RECONSTRUCT_NORMAL_MEDIUM _RECONSTRUCT_NORMAL_HIGH
            #pragma multi_compile_local _ _ORTHOGRAPHIC
            #include "HBAOPass.hlsl"
            #pragma vertex vert
            #pragma fragment frag

            ENDHLSL
        }

        Pass
        {
            
            Name "HBAO Blur"

            HLSLPROGRAM

            #pragma multi_compile_fragment _ _GBUFFER_NORMALS_OCT
            #pragma multi_compile_local _SOURCE_DEPTH _SOURCE_DEPTH_NORMALS
            #pragma multi_compile_local _RECONSTRUCT_NORMAL_LOW _RECONSTRUCT_NORMAL_MEDIUM _RECONSTRUCT_NORMAL_HIGH
            #pragma multi_compile_local _ _ORTHOGRAPHIC
            #include "HBAOPass.hlsl"
            #pragma vertex vert
            #pragma fragment BlurPassFragment

            ENDHLSL
        }
    }
}