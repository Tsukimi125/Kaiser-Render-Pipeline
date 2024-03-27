#ifndef KAISER_SCREEN_SPACE_RAY_TRACING
#define KAISER_SCREEN_SPACE_RAY_TRACING

#include "../ShaderLibrary/RandomFunctions.hlsl"

// Help functions
float2 rand(float2 a)
{
    return float2(
        frac(sin(dot(a.xy, float2(12.9898, 78.233))) * 43758.5453),
        frac(sin(dot(a.xy, float2(62.3587, 28.148))) * 17859.2547)
    );
}

float3x3 GetTangentBasis(float3 TangentZ)
{
    float3 UpVector = abs(TangentZ.z) < 0.999 ? float3(0, 0, 1):float3(1, 0, 0);
    float3 TangentX = normalize(cross(UpVector, TangentZ));
    float3 TangentY = cross(TangentZ, TangentX);
    return float3x3(TangentX, TangentY, TangentZ);
}

float3 TangentToWorld_(float3 Vec, float3 TangentZ)
{
    return mul(Vec, GetTangentBasis(TangentZ));
}

float4 TangentToWorld(float3 Vec, float4 TangentZ)
{
    half3 T2W = TangentToWorld_(Vec, TangentZ.rgb);
    return half4(T2W, TangentZ.a);
}

struct Ray
{
    float3 pos;
    float3 dir;
};

struct RayHit
{
    bool hitSuccessful;
    float2 hitUV;
};

struct RayMarchingSetting
{
    half stepSize;
    half maxSteps;
    half maxDistance;
    bool useBinarySearch;
};

RayHit InitializeRayHit()
{
    RayHit rayHit;
    rayHit.hitSuccessful = false;
    rayHit.hitUV = float2(0.0, 0.0);
    return rayHit;
}

RayHit LinearTrace(
    Ray ray, Texture2D _CameraDepthTexture, SamplerState sampler_CameraDepthTexture, uint2 random,
    out bool hitSuccessful, out float2 hitUV)
{
    RayHit rayHit = InitializeRayHit();
    float raymarchingThickness = 1.0;
    float stepSize = 0.5;
    float stepMultiplier = 1.2;
    float3 rayWorldPos = ray.pos;
    float3 rayNDCPos = float3(0.0, 0.0, 0.0);

    float p1;

    hitSuccessful = false;

    bool startBinarySearch = false;
    [loop]
    for (uint i = 1; i <= 128; i++)
    {
        float2 hash = frac(Hammersley16(i, (uint)128, random));
        rayWorldPos += ray.dir * stepSize * (1 + hash.x);
        rayNDCPos = ComputeNormalizedDeviceCoordinatesWithZ(rayWorldPos, UNITY_MATRIX_VP);
        
        bool isScreenSpace = (rayNDCPos.x > 0.0 && rayNDCPos.y > 0.0 && rayNDCPos.x < 1.0 && rayNDCPos.y < 1.0) ? true:false;
        if (!isScreenSpace)
            break;
        
        float deviceDepth = SAMPLE_TEXTURE2D_X_LOD(_CameraDepthTexture, sampler_CameraDepthTexture, rayNDCPos.xy, 0).r; // z buffer depth
        float sceneDepth = LinearEyeDepth(deviceDepth, _ZBufferParams);
        float hitDepth = LinearEyeDepth(rayNDCPos.z, _ZBufferParams);
        float depthDiff = sceneDepth - hitDepth;
        
        bool isSky;
        #ifdef UNITY_REVERSED_Z
            isSky = deviceDepth == 0.0 ? true:false;
        #else
            isSky = deviceDepth == 1.0 ? true:false; // OpenGL Platforms.
        #endif

        half sign = FastSign(depthDiff);

        startBinarySearch = startBinarySearch || (sign == -1) ? true:false;
        if (startBinarySearch && FastSign(stepSize) != sign)
        {
            stepSize = stepSize * sign * 0.5;
            raymarchingThickness = raymarchingThickness * 0.5;
        }
        
        hitSuccessful = (depthDiff <= 0.0 && (depthDiff >= -raymarchingThickness) && !isSky) ? true:false;
        if (hitSuccessful)
        {
            break;
        }
        stepSize *= stepMultiplier * (1 + hash.y);
    }

    hitUV = rayNDCPos.xy;
    return rayHit;
}




#endif