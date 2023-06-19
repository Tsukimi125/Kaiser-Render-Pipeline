#ifndef KAISER_TEMPORAL
#define KAISER_TEMPORAL

#include "Packages/com.unity.render-pipelines.core/ShaderLibrary/SpaceTransforms.hlsl"

inline half2 GetMotionVector(half SceneDepth, half2 inUV, half4x4 _InverseViewProjectionMatrix, half4x4 _PrevViewProjectionMatrix, half4x4 _ViewProjectionMatrix)
{
    half3 screenPos = ComputeClipSpacePosition(inUV, SceneDepth);
    half4 worldPos = half4(ComputeWorldSpacePosition(inUV, SceneDepth, _InverseViewProjectionMatrix), 1);

    half4 prevClipPos = mul(_PrevViewProjectionMatrix, worldPos);
    half4 curClipPos = mul(_ViewProjectionMatrix, worldPos);

    half2 prevHPos = prevClipPos.xy / prevClipPos.w;
    half2 curHPos = curClipPos.xy / curClipPos.w;

    half2 vPosPrev = (prevHPos.xy + 1) / 2;
    half2 vPosCur = (curHPos.xy + 1) / 2;
    return vPosCur - vPosPrev;
}

inline float pow2(float x)
{
    return x * x;
}

inline void ResolverAABB(Texture2D currColor, SamplerState colorSampler, half Sharpness, half ExposureScale, half AABBScale, half2 uv, half2 TexelSize, inout half Variance, inout half4 MinColor, inout half4 MaxColor, inout half4 FilterColor)
{
    const int2 SampleOffset[9] = {
        int2(-1.0, -1.0), int2(0.0, -1.0), int2(1.0, -1.0), int2(-1.0, 0.0), int2(0.0, 0.0), int2(1.0, 0.0), int2(-1.0, 1.0), int2(0.0, 1.0), int2(1.0, 1.0)
    };
    half4 SampleColors[9];

    for (uint i = 0; i < 9; i++)
    {
        #if AA_BicubicFilter
            half4 BicubicSize = half4(TexelSize, 1.0 / TexelSize);
            SampleColors[i] = Texture2DSampleBicubic(currColor, uv + (SampleOffset[i] / TexelSize), BicubicSize.xy, BicubicSize.zw);
        #else
            SampleColors[i] = currColor.SampleLevel(colorSampler, uv + (SampleOffset[i] / TexelSize), 0);
        #endif
    }

    #if AA_Filter
        half SampleWeights[9];
        for (uint j = 0; j < 9; j++)
        {
            SampleWeights[j] = HdrWeight4(SampleColors[j].rgb, ExposureScale);
        }

        half TotalWeight = 0;
        for (uint k = 0; k < 9; k++)
        {
            TotalWeight += SampleWeights[k];
        }
        SampleColors[4] = (SampleColors[0] * SampleWeights[0] + SampleColors[1] * SampleWeights[1] + SampleColors[2] * SampleWeights[2] + SampleColors[3] * SampleWeights[3] + SampleColors[4] * SampleWeights[4] + SampleColors[5] * SampleWeights[5] + SampleColors[6] * SampleWeights[6] + SampleColors[7] * SampleWeights[7] + SampleColors[8] * SampleWeights[8]) / TotalWeight;
    #endif

    half4 m1 = 0.0; half4 m2 = 0.0;
    for (uint x = 0; x < 9; x++)
    {
        m1 += SampleColors[x];
        m2 += SampleColors[x] * SampleColors[x];
    }

    half4 mean = m1 / 9.0;
    half4 stddev = sqrt((m2 / 9.0) - pow2(mean));
    
    MinColor = mean - AABBScale * stddev;
    MaxColor = mean + AABBScale * stddev;

    FilterColor = SampleColors[4];
    MinColor = min(MinColor, FilterColor);
    MaxColor = max(MaxColor, FilterColor);

    half4 TotalVariance = 0;
    for (uint z = 0; z < 9; z++)
    {
        TotalVariance += pow2(Luminance(SampleColors[z]) - Luminance(mean));
    }
    Variance = saturate((TotalVariance / 9) * 256);
    Variance *= FilterColor.a;
}

#endif