Shader "Hidden/Kaiser RP/StochasticSSR"
{
    SubShader
    {
        Cull Off
        ZTest Always
        Zwrite Off

        HLSLINCLUDE
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
        #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Common.hlsl"
        #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/SpaceTransforms.hlsl"
        #include "StochasticSSRPass.hlsl"
        ENDHLSL

        Pass
        {
            Name "Prepare Hierarchical Z"

            HLSLPROGRAM
            #pragma target 3.5
            #pragma vertex DefaultPassVertex
            #pragma fragment GetHierarchicalZBuffer
            ENDHLSL
        }
    }
}
