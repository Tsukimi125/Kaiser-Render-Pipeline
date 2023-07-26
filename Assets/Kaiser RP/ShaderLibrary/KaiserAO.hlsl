#ifndef KAISER_AMBIENT_OCCLUSION
#define KAISER_AMBIENT_OCCLUSION

float Hash(float2 p)
{
    return frac(sin(dot(p, float2(1.9, 7.2))) * 4.5);
}



float3 MinDiff(float3 p, float3 p1, float3 p2)
{
    float3 v1 = p1 - p;
    float3 v2 = p - p2;
    return (length(v1) < length(v2)) ? v1 : v2;
}

float FallOff(float dist, float radius)
{
    return saturate(1 - (dist * dist / (radius * radius))); // if dist >= _Radius saturate(FallOff(dist))=0 ao=0

}

float GetTan(float3 v)
{
    return v.z * rsqrt(dot(v.xy, v.xy));
}

float TanToSin(float x)
{
    return x * rsqrt(x * x + 1.0);
}

float2 RotateDirections(float2 dir, float2 CosSin)
{
    return float2(
        dir.x * CosSin.x - dir.y * CosSin.y,
        dir.x * CosSin.y + dir.y * CosSin.x
    );
}

float2 SnapUVOffset(float2 uv, float2 bufferSize, float2 invBufferSize)
{
    return round(uv * bufferSize) * invBufferSize;
}

#endif