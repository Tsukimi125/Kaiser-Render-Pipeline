#ifndef KAISER_HBAO_PASS_INCLUDEDk
#define KAISER_HBAO_PASS_INCLUDED


// #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Common.hlsl"
// #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Input.hlsl"
#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
#include "Packages/com.unity.render-pipelines.core/ShaderLibrary/SpaceTransforms.hlsl"


#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareDepthTexture.hlsl"
#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareNormalsTexture.hlsl"

float _Intensity;
float _Radius;
int _SampleNums;
float _MaxDistance;
float4 _ProjectionParams2;
StructuredBuffer<float2> _NoiseCB;

// Reconstruction VS

float SampleLinearDepth(float2 uv)
{
    float depth = SampleSceneDepth(uv);
    return LinearEyeDepth(depth, _ZBufferParams);
}

void SampleDepthNormalView(float2 uv, out float depth, out float3 normalVS, out float3 positionVS)
{
    depth = SampleSceneDepth(uv);
    positionVS = ComputeViewSpacePosition(uv, depth, UNITY_MATRIX_I_P);
    positionVS.z = -positionVS.z;
    normalVS = float3(SampleSceneNormals(uv));

}

// Trigonometric function utility

static float SSAORandomUV[40] = {
    0.00000000, // 00
    0.33984375, // 01
    0.75390625, // 02
    0.56640625, // 03
    0.98437500, // 04
    0.07421875, // 05
    0.23828125, // 06
    0.64062500, // 07
    0.35937500, // 08
    0.50781250, // 09
    0.38281250, // 10
    0.98437500, // 11
    0.17578125, // 12
    0.53906250, // 13
    0.28515625, // 14
    0.23137260, // 15
    0.45882360, // 16
    0.54117650, // 17
    0.12941180, // 18
    0.64313730, // 19

    0.92968750, // 20
    0.76171875, // 21
    0.13333330, // 22
    0.01562500, // 23
    0.00000000, // 24
    0.10546875, // 25
    0.64062500, // 26
    0.74609375, // 27
    0.67968750, // 28
    0.35156250, // 29
    0.49218750, // 30
    0.12500000, // 31
    0.26562500, // 32
    0.62500000, // 33
    0.44531250, // 34
    0.17647060, // 35
    0.44705890, // 36
    0.93333340, // 37
    0.87058830, // 38
    0.56862750, // 39

};

float Hash(float2 p)
{
    return frac(sin(dot(p, float2(12.9898, 78.233))) * 43758.5453);
}

float3 GetRandomVec(float2 p)
{
    float3 vec = float3(0, 0, 0);
    vec.x = Hash(p) * 2 - 1;
    vec.y = Hash(p * p) * 2 - 1;
    vec.z = Hash(p * p * p) * 2 - 1;
    return normalize(vec);
}

float3 GetRandomVecHalf(float2 p)
{
    float3 vec = float3(0, 0, 0);
    vec.x = Hash(p) * 2 - 1;
    vec.y = Hash(p * p) * 2 - 1;
    vec.z = saturate(Hash(p * p * p) + 0.2);
    return normalize(vec);
}

// Blur Functions

TEXTURE2D(_AOTex);
SAMPLER(sampler_AOTex);

float _BlurSharpness = 8.0f;
float2 _BlurDeltaUV;

#define KERNEL_RADIUS 2

void FetchAOAndDepth(float2 uv, inout float ao, inout float depth)
{
    ao = SAMPLE_TEXTURE2D_LOD(_AOTex, sampler_AOTex, uv, 0).r;
    depth = SampleSceneDepth(uv);
    depth = Linear01Depth(depth, _ZBufferParams);
}

float CrossBilateralWeight(float r, float d, float d0)
{
    float blurSigma = KERNEL_RADIUS * 0.5;
    float blurFalloff = 1.0 / (2.0 * blurSigma * blurSigma);

    float dz = (d0 - d) * _ProjectionParams.z * _BlurSharpness;
    return exp2(-r * r * blurFalloff - dz * dz);
}

void ProcessSample(float ao, float d, float r, float d0, inout float totalAO, inout float totalW)
{
    float w = CrossBilateralWeight(r, d, d0);
    totalW += w;
    totalAO += w * ao;
}

void ProcessRadius(float2 uv0, float2 deltaUV, float d0, inout float totalAO, inout float totalW)
{
    float ao;
    float d;
    float2 uv;

    UNITY_UNROLL
    for (int r = 1; r <= KERNEL_RADIUS; r++)
    {
        uv = uv0 + r * deltaUV;
        FetchAOAndDepth(uv, ao, d);
        ProcessSample(ao, d, r, d0, totalAO, totalW);
    }
}

struct Attributes
{
    uint vertexID : SV_VertexID;
};

struct Varyings
{
    float4 pos : SV_Position;
    float2 uv : TEXCOORD0;
};

Varyings vert(Attributes input)
{
    Varyings output;
    output.pos = GetFullScreenTriangleVertexPosition(input.vertexID);
    output.uv = GetFullScreenTriangleTexCoord(input.vertexID);
    return output;
}

float frag(Varyings input) : SV_Target
{
    float2 uv = input.uv;
    float depth;
    float3 normalVS;
    float3 positionVS;
    SampleDepthNormalView(uv, depth, normalVS, positionVS);

    float occluded = 0;
    float3 samplePositionVS;
    float4 samplePositionCS, samplePositionSS;
    float sampleDepth;

    for (int i = 0; i < _SampleNums; i++)
    {

        float3 offset = GetRandomVec(i * uv);

        offset = normalize(offset) * _Radius;
    
        samplePositionVS = positionVS + offset;
        
        samplePositionCS = mul(GetViewToHClipMatrix(), float4(samplePositionVS, 1.0));
        samplePositionSS = ComputeScreenPos(samplePositionCS);
        sampleDepth = SampleSceneDepth(samplePositionSS.xy / samplePositionSS.w);
        float3 positionVS2;
        float2 newUV = saturate(samplePositionSS.xy / samplePositionSS.w);
        SampleDepthNormalView(newUV, depth, normalVS, positionVS2);

        occluded += (samplePositionVS.z < positionVS2.z) ? 1 : 0;

    }
    // if (occluded < 0.5 * _SampleNums)
    // {
    //     return float4(1,0,0,0);
    // }
    return saturate(1.0 - (occluded - 0.525 * _SampleNums) / _SampleNums);
}

half BlurPassFragment(Varyings input) : SV_Target
{
    float2 uv = input.uv;
    float2 deltaUV = _BlurDeltaUV;

    float totalAO;
    float depth;
    FetchAOAndDepth(uv, totalAO, depth);
    float totalW = 1.0;

    ProcessRadius(uv, -deltaUV, depth, totalAO, totalW);
    ProcessRadius(uv, +deltaUV, depth, totalAO, totalW);

    totalAO /= totalW;

    return totalAO;
}

#endif // KAISER_HBAO_PASS_INCLUDED
