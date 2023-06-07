#ifndef KAISER_SSRT
#define KAISER_SSRT

#include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Common.hlsl"

float3 GetWorldSpacePosition(float2 uv, float depth)
{
    return ComputeWorldSpacePosition(uv, depth, UNITY_MATRIX_I_VP);
}

float3 GetViewSpacePosition(float2 uv, float depth)
{
    return ComputeViewSpacePosition(uv, depth, UNITY_MATRIX_I_P);
}

float3x3 GetTangentBasis(float3 TangentZ) {
	float3 UpVector = abs(TangentZ.z) < 0.999 ? float3(0, 0, 1) : float3(1, 0, 0);
	float3 TangentX = normalize(cross( UpVector, TangentZ));
	float3 TangentY = cross(TangentZ, TangentX);
	return float3x3(TangentX, TangentY, TangentZ);
}


float GetMarchSize(float2 start, float2 end, float2 samplerPos)
{
    float2 dir = abs(end - start);
    return length(float2(min(dir.x, samplerPos.x), min(dir.y, samplerPos.y)));
}

float4 HizTrace_Base(int Hiz_MaxLevel, int Hiz_StartLevel, int Hiz_StopLevel,
                int steps, float thickness, float2 rayCastSize, 
                float3 rayStart, float3 rayDir,
                Texture2D depthTexture, SamplerState depthSampler)
{
    float sampleSize = GetMarchSize(rayStart.xy, rayStart.xy + rayDir.xy, rayCastSize);
    float3 samplePos = rayStart + rayDir * (sampleSize);
    int level = Hiz_StartLevel;
    float mask = 0.0;

    [loop]
    for (int i = 0; i < steps; i++)
    {
        float2 cellCount = rayCastSize * exp2(level + 1.0);
        float newSamplerSize = GetMarchSize(samplePos.xy, samplePos.xy + rayDir.xy, cellCount);
        float3 newSamplePos = samplePos + rayDir * newSamplerSize;
        float sampleMinDepth = depthTexture.SampleLevel(depthSampler, newSamplePos.xy, level).r;
        // float sampleMinDepth = Texture2DSampleLevel(SceneDepth, SceneDepth_Sampler, newSamplePos.xy, level);

        [flatten]
        if (sampleMinDepth < newSamplePos.z)
        {
            level = min(Hiz_MaxLevel, level + 1.0);
            samplePos = newSamplePos;
        }
        else
        {
            level--;
        }

        [branch]
        if (level < Hiz_StopLevel)
        {
            float delta = (-LinearEyeDepth(sampleMinDepth, _ZBufferParams)) - (-LinearEyeDepth(samplePos.z, _ZBufferParams));
            mask = delta <= thickness && i > 0.0;
            
            return float4(samplePos, steps);
            // return float4(samplePos, mask);
        }
    }
    return float4(samplePos, steps);
}

float4 Hierarchical_Z_Trace1(int HiZ_Max_Level, int HiZ_Start_Level, int HiZ_Stop_Level, int NumSteps, float thickness, float2 RayCastSize, float3 rayStart, float3 rayDir, Texture2D SceneDepth, SamplerState SceneDepth_Sampler)
{
    float SamplerSize = GetMarchSize(rayStart.xy, rayStart.xy + rayDir.xy, RayCastSize);
    float3 samplePos = rayStart + rayDir * (SamplerSize);
    int level = HiZ_Start_Level; float mask = 0.0;
    float sum = 0.0;
    float sum2 = 0.0;
    
    UNITY_LOOP
    for (int i = 0; i < NumSteps; i++)
    {
        float2 cellCount = RayCastSize * exp2(level + 1.0);
        float newSamplerSize = GetMarchSize(samplePos.xy, samplePos.xy + rayDir.xy, cellCount);
        float3 newSamplePos = samplePos + rayDir * newSamplerSize;
        float sampleMinDepth = SAMPLE_TEXTURE2D_X_LOD(SceneDepth, SceneDepth_Sampler, newSamplePos.xy, level).r;

        UNITY_FLATTEN
        if (sampleMinDepth < newSamplePos.z) {
            level = min(HiZ_Max_Level, level + 1.0);
            samplePos = newSamplePos;
        } else {
            level--;
        }

        UNITY_BRANCH
        if (level < HiZ_Stop_Level) {
            float delta = (-LinearEyeDepth(sampleMinDepth, _ZBufferParams)) - (-LinearEyeDepth(samplePos.z, _ZBufferParams));
            mask = delta <= thickness && i > 0.0;
            sum /= NumSteps;
            
            return float4(samplePos, mask);
        }
        sum2+=12;
    }
    // sum2 /= NumSteps;
    // return float4(1.0,sum2,NumSteps / 128,sum2);
    return float4(samplePos, mask);
}


float GetStepScreenFactorToClipAtScreenEdge(float2 RayStartScreen, float2 RayStepScreen)
{
	const float RayStepScreenInvFactor = 0.5 * length(RayStepScreen);
	const float2 S = 1 - max(abs(RayStepScreen + RayStartScreen * RayStepScreenInvFactor) - RayStepScreenInvFactor, 0.0f) / abs(RayStepScreen);
	const float RayStepFactor = min(S.x, S.y) / RayStepScreenInvFactor;
	return RayStepFactor;
}

#endif