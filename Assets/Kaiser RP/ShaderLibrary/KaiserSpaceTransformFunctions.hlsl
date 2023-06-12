#ifndef KAISER_SPACE_TRANSFORM
#define KAISER_SPACE_TRANSFORM

float3 Kaiser_GetNDCPos(float2 uv, float depth)
{
    return float3(uv * 2 - 1, depth);
}

float3 Kaiser_GetWorldPos(float3 ndcPos)
{
    float4 worldPos = mul(UNITY_MATRIX_I_VP, float4(ndcPos, 1.0));
    return worldPos.xyz / worldPos.w;
}

float3 Kaiser_GetViewPos(float3 ndcPos)
{
    float4 viewPos = mul(UNITY_MATRIX_I_P, float4(ndcPos, 1.0));
    return viewPos.xyz / viewPos.w;
}

float3 Kaiser_GetViewDir(float3 worldPos)
{
    return normalize(worldPos - GetCameraPositionWS());
}

#endif