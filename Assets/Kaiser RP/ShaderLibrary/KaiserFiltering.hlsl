#ifndef KAISER_FILTERING
#define KAISER_FILTERING

void GetAo_Depth(Texture2D _SourceTexture, Texture2D _DepthTexture, SamplerState textureSampler, float2 uv, inout float3 AO_RO, inout float AO_Depth)
{
    float3 SourceColor = _SourceTexture.SampleLevel(textureSampler, uv, 0).rgb;
    float Depth = _DepthTexture.SampleLevel(textureSampler, uv, 0).r;
    AO_RO = SourceColor;
    AO_Depth = Depth;
}

float CrossBilateralWeight(float BLUR_RADIUS, float r, float Depth, float originDepth)
{
    const float BlurSigma = BLUR_RADIUS * 0.5;
    const float BlurFalloff = 1.0 / (2.0 * BlurSigma * BlurSigma);

    float dz = (originDepth - Depth) * _ProjectionParams.z * 0.25;
    return exp2(-r * r * BlurFalloff - dz * dz);
}

void ProcessSample(float4 AO_RO_Depth, float BLUR_RADIUS, float r, float originDepth, inout float3 totalAO_RO, inout float totalWeight)
{
    float weight = CrossBilateralWeight(BLUR_RADIUS, r, originDepth, AO_RO_Depth.w);
    totalWeight += weight;
    totalAO_RO += weight * AO_RO_Depth.xyz;
}

void ProcessRadius(Texture2D _SourceTexture, Texture2D _DepthTexture, SamplerState textureSampler, float2 uv0, float2 deltaUV, float BLUR_RADIUS, float originDepth, inout float3 totalAO_RO, inout float totalWeight)
{
    float r = 1.0;
    float z = 0.0;
    float2 uv = 0.0;
    float3 AO_RO = 0.0;

    [unroll(8)]
    for (; r <= BLUR_RADIUS / 2.0; r += 1.0)
    {
        uv = uv0 + r * deltaUV;
        GetAo_Depth(_SourceTexture, _DepthTexture, textureSampler, uv, AO_RO, z);
        ProcessSample(float4(AO_RO, z), BLUR_RADIUS, r, originDepth, totalAO_RO, totalWeight);
    }

    [unroll(8)]
    for (; r <= BLUR_RADIUS; r += 2.0)
    {
        uv = uv0 + (r + 0.5) * deltaUV;
        GetAo_Depth(_SourceTexture, _DepthTexture, textureSampler, uv, AO_RO, z);
        ProcessSample(float4(AO_RO, z), BLUR_RADIUS, r, originDepth, totalAO_RO, totalWeight);
    }
}

float4 BilateralBlur(float BLUR_RADIUS, float2 uv0, float2 deltaUV, Texture2D _SourceTexture, Texture2D _DepthTexture, SamplerState textureSampler)
{
    float totalWeight = 1.0;
    float Depth = 0.0;
    float3 totalAOR = 0.0;
    GetAo_Depth(_SourceTexture, _DepthTexture, textureSampler, uv0, totalAOR, Depth);
    
    ProcessRadius(_SourceTexture, _DepthTexture, textureSampler, uv0, -deltaUV, BLUR_RADIUS, Depth, totalAOR, totalWeight);
    ProcessRadius(_SourceTexture, _DepthTexture, textureSampler, uv0, deltaUV, BLUR_RADIUS, Depth, totalAOR, totalWeight);
    
    totalAOR /= totalWeight;
    return float4(totalAOR, Depth);
}




#endif