Shader"Hidden/Universal Render Pipeline/TAAShader"
{
    Properties
    {
        _MainTex("Source", 2D) = "white" {}
    }

    HLSLINCLUDE
#pragma exclude_renderers gles psp2
#pragma target 3.5
#pragma multi_compile _High_TAA _Middle_TAA _Low_TAA
#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
#include "Packages/com.unity.render-pipelines.universal/Shaders/PostProcessing/Common.hlsl"
#define HALF_MAX_MINUS1 65472.0

    TEXTURE2D_X(_MainTex);
    uniform float4 _MainTex_TexelSize;
    TEXTURE2D_X(_TAA_PreTexture);
    TEXTURE2D_X_FLOAT(_CameraDepthTexture);
    uniform float4 _CameraDepthTexture_TexelSize;
    TEXTURE2D_X(_CameraMotionVectorsTexture);
    float4x4 _Preview_VP;
    float4x4 _Inv_view_jittered;
    float4x4 _Inv_proj_jittered;
    float4 _Jitter_Blend;

    struct AttributesTAA
    {
        float4 positionOS : POSITION;
        float2 uv : TEXCOORD0;
        UNITY_VERTEX_INPUT_INSTANCE_ID
    };

    struct VaryingsTAA
    {
        float4 positionCS : SV_POSITION;
        float4 uv : TEXCOORD0;
        UNITY_VERTEX_OUTPUT_STEREO
    };

    VaryingsTAA TAAVert(AttributesTAA input)
    {
        VaryingsTAA output;
        UNITY_SETUP_INSTANCE_ID(input);
        UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(output);

        output.positionCS = TransformObjectToHClip(input.positionOS.xyz);

        float4 projPos = output.positionCS * 0.5;
        projPos.xy = projPos.xy + projPos.w;

        output.uv.xy = UnityStereoTransformScreenSpaceTex(input.uv);
        output.uv.zw = projPos.xy;

        return output;
    }

    float2 HistoryPosition(float2 unJitteredUV)
    {
        float depth = SAMPLE_TEXTURE2D_X(_CameraDepthTexture, sampler_PointClamp, unJitteredUV).r;

#if UNITY_REVERSED_Z
        depth = 1.0 - depth;
#endif
        depth = 2.0 * depth - 1.0;

#if UNITY_UV_STARTS_AT_TOP
        unJitteredUV.y = 1.0f - unJitteredUV.y;
#endif

        float3 viewPos = ComputeViewSpacePosition(unJitteredUV, depth, _Inv_proj_jittered);
        float4 worldPos = float4(mul(unity_CameraToWorld, float4(viewPos, 1.0)).xyz, 1.0);

        float4 historyNDC = mul(_Preview_VP, worldPos);
        historyNDC /= historyNDC.w;
        historyNDC.xy = historyNDC.xy * 0.5f + 0.5f;
        return historyNDC.xy;
    }

    float2 GetClosestFragment(float2 uv)
    {
        const float2 k = _CameraDepthTexture_TexelSize.xy;

        const float4 neighborhood = float4(
                SAMPLE_DEPTH_TEXTURE(_CameraDepthTexture, sampler_PointClamp, uv - k),
                SAMPLE_DEPTH_TEXTURE(_CameraDepthTexture, sampler_PointClamp, uv + float2(k.x, -k.y)),
                SAMPLE_DEPTH_TEXTURE(_CameraDepthTexture, sampler_PointClamp, uv + float2(-k.x, k.y)),
                SAMPLE_DEPTH_TEXTURE(_CameraDepthTexture, sampler_PointClamp, uv + k)
            );
    #if defined(UNITY_REVERSED_Z)
        #define COMPARE_DEPTH(a, b) step(b, a)
    #else
        #define COMPARE_DEPTH(a, b) step(a, b)
    #endif
        float3 result = float3(0.0, 0.0, SAMPLE_DEPTH_TEXTURE(_CameraDepthTexture, sampler_PointClamp, uv));
        result = lerp(result, float3(-1.0, -1.0, neighborhood.x), COMPARE_DEPTH(neighborhood.x, result.z));
        result = lerp(result, float3(1.0, -1.0, neighborhood.y), COMPARE_DEPTH(neighborhood.y, result.z));
        result = lerp(result, float3(-1.0, 1.0, neighborhood.z), COMPARE_DEPTH(neighborhood.z, result.z));
        result = lerp(result, float3(1.0, 1.0, neighborhood.w), COMPARE_DEPTH(neighborhood.w, result.z));

        return (uv + result.xy * k);
    }

    float4 ClipAABB(float3 aabbMin, float3 aabbMax, float4 avg, float4 preColor)
    {
        float3 p_clip = 0.5 * (aabbMax + aabbMin);
        float3 e_clip = 0.5 * (aabbMax - aabbMin) + FLT_EPS;

        float4 v_clip = preColor - float4(p_clip, avg.w);
        float3 v_unit = v_clip.xyz / e_clip;
        float3 a_unit = abs(v_unit);
        float ma_unit = max(a_unit.x, max(a_unit.y, a_unit.z));

        if (ma_unit > 1.0)
            return float4(p_clip, avg.w) + v_clip / ma_unit;
        return preColor;
    }

    float4 RGB2YCoCgR(float4 rgbColor)
    {
        float4 YCoCgRColor;

        YCoCgRColor.y = rgbColor.r - rgbColor.b;
        float temp = rgbColor.b + YCoCgRColor.y / 2;
        YCoCgRColor.z = rgbColor.g - temp;
        YCoCgRColor.x = temp + YCoCgRColor.z / 2;
        YCoCgRColor.w = rgbColor.w;

        return YCoCgRColor;
    }

    float4 YCoCgR2RGB(float4 YCoCgRColor)
    {
        float4 rgbColor;

        float temp = YCoCgRColor.x - YCoCgRColor.z / 2;
        rgbColor.g = YCoCgRColor.z + temp;
        rgbColor.b = temp - YCoCgRColor.y / 2;
        rgbColor.r = rgbColor.b + YCoCgRColor.y;
        rgbColor.w = YCoCgRColor.w;

        return rgbColor;
    }

    float4 ToneMap(float4 color)
    {
        return color / (1 + Luminance(color));
    }

    float4 UnToneMap(float4 color)
    {
        return color / (1 - Luminance(color));
    }

    float4 TAAFragment(VaryingsTAA input) : SV_Target
    {
        UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(input);
        float2 jitteredUV = UnityStereoTransformScreenSpaceTex(input.uv);
        float2 unJitteredUV = jitteredUV - _Jitter_Blend.xy;
        float4 curColor = SAMPLE_TEXTURE2D_X(_MainTex, sampler_LinearClamp, unJitteredUV);

        float4 colorMin;
        float4 colorMax;
        float4 colorAvg;

        #if defined(_High_TAA)
        float2 du = float2(_MainTex_TexelSize.x, 0.0f);
        float2 dv = float2(0.0f, _MainTex_TexelSize.y);
        float4 colorTL = RGB2YCoCgR(ToneMap(SAMPLE_TEXTURE2D(_MainTex, sampler_LinearClamp, unJitteredUV - du - dv)));
        float4 colorTC = RGB2YCoCgR(ToneMap(SAMPLE_TEXTURE2D(_MainTex, sampler_LinearClamp, unJitteredUV - dv)));
        float4 colorTR = RGB2YCoCgR(ToneMap(SAMPLE_TEXTURE2D(_MainTex, sampler_LinearClamp, unJitteredUV + du - dv)));
        float4 colorML = RGB2YCoCgR(ToneMap(SAMPLE_TEXTURE2D(_MainTex, sampler_LinearClamp, unJitteredUV - du)));
        float4 colorMC = RGB2YCoCgR(ToneMap(SAMPLE_TEXTURE2D(_MainTex, sampler_LinearClamp, unJitteredUV)));
        float4 colorMR = RGB2YCoCgR(ToneMap(SAMPLE_TEXTURE2D(_MainTex, sampler_LinearClamp, unJitteredUV + du)));
        float4 colorBL = RGB2YCoCgR(ToneMap(SAMPLE_TEXTURE2D(_MainTex, sampler_LinearClamp, unJitteredUV - du + dv)));
        float4 colorBC = RGB2YCoCgR(ToneMap(SAMPLE_TEXTURE2D(_MainTex, sampler_LinearClamp, unJitteredUV + dv)));
        float4 colorBR = RGB2YCoCgR(ToneMap(SAMPLE_TEXTURE2D(_MainTex, sampler_LinearClamp, unJitteredUV + du + dv)));
        colorMin = min(colorTL, min(colorTC, min(colorTR, min(colorML, min(colorMC, min(colorMR, min(colorBL, min(colorBC, colorBR))))))));
        colorMax = max(colorTL, max(colorTC, max(colorTR, max(colorML, max(colorMC, max(colorMR, max(colorBL, max(colorBC, colorBR))))))));
        colorAvg = (colorTL + colorTC + colorTR + colorML + colorMC + colorMR + colorBL + colorBC + colorBR) / 9.0;

        #elif defined(_Middle_TAA)
        float2 offset0 = float2(-_MainTex_TexelSize.x, _MainTex_TexelSize.y);
        float2 offset1 = float2(_MainTex_TexelSize.x, -_MainTex_TexelSize.y);
        float4 color0 = RGB2YCoCgR(ToneMap(SAMPLE_TEXTURE2D(_MainTex, sampler_LinearClamp, unJitteredUV - offset0)));
        float4 color1 = RGB2YCoCgR(ToneMap(SAMPLE_TEXTURE2D(_MainTex, sampler_LinearClamp, unJitteredUV + offset0)));
        float4 color2 = RGB2YCoCgR(ToneMap(SAMPLE_TEXTURE2D(_MainTex, sampler_LinearClamp, unJitteredUV - offset1)));
        float4 color3 = RGB2YCoCgR(ToneMap(SAMPLE_TEXTURE2D(_MainTex, sampler_LinearClamp, unJitteredUV + offset1)));
        float4 color4 = RGB2YCoCgR(ToneMap(SAMPLE_TEXTURE2D(_MainTex, sampler_LinearClamp, unJitteredUV)));
        colorMin = min(color0, min(color1, min(color2, min(color3, color4))));
        colorMax = max(color0, max(color1, max(color2, max(color3, color4))));
        colorAvg = (color0 + color1 + color2 + color3 + color4) / 5.0;

        #elif defined(_Low_TAA)
        float2 offset = float2(_MainTex_TexelSize.x, _MainTex_TexelSize.y);
        float4 color0 = RGB2YCoCgR(ToneMap(SAMPLE_TEXTURE2D(_MainTex, sampler_LinearClamp, unJitteredUV - offset)));
        float4 color1 = RGB2YCoCgR(ToneMap(SAMPLE_TEXTURE2D(_MainTex, sampler_LinearClamp, unJitteredUV + offset)));
        float4 color2 = RGB2YCoCgR(ToneMap(SAMPLE_TEXTURE2D(_MainTex, sampler_LinearClamp, unJitteredUV)));
        colorMin = min(color0, min(color1, color2));
        colorMax = max(color0, max(color1, color2));
        colorAvg = (color0 + color1 + color2) / 3.0;
        #endif

        float2 historyUV = HistoryPosition(unJitteredUV);
        float4 preColor = SAMPLE_TEXTURE2D_X(_TAA_PreTexture, sampler_LinearClamp, historyUV);
        preColor = RGB2YCoCgR(ToneMap(preColor));
        float4 clampedColor = ClipAABB(colorMin.rgb, colorMax.rgb, colorAvg, preColor);
        clampedColor = UnToneMap(YCoCgR2RGB(clampedColor));
        preColor = clampedColor;
        
        float4 result = curColor * _Jitter_Blend.z + preColor * (1 - _Jitter_Blend.z);
        result = clamp(result, 0.0, HALF_MAX_MINUS1);
        return result;
    }
        ENDHLSL
    SubShader
    {
        Tags
        {
            "RenderType" = "Opaque" "RenderPipeline" = "UniversalPipeline"
        }
            ZTest Always
            ZWrite Off
            Cull Off

            Pass
        {
            Name "TAA"
            HLSLPROGRAM
            #pragma vertex TAAVert
            #pragma fragment TAAFragment
            ENDHLSL
        }
    }
}