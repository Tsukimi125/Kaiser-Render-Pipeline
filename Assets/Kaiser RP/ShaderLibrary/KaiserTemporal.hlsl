#ifndef KAISER_TEMPORAL
#define KAISER_TEMPORAL

#include "Packages/com.unity.render-pipelines.core/ShaderLibrary/SpaceTransforms.hlsl"

float4 ClipAABB(float3 aabbMin, float3 aabbMax, float4 avg, float4 preColor)
{
    float3 p_clip = 0.5 * (aabbMax + aabbMin);
    float3 e_clip = 0.5 * (aabbMax - aabbMin) + 0.00001;

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
#endif