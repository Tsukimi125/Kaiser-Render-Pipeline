
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

float4 HizTrace_Base(int hizMaxLevel, int hizStartLevel, int hizStopLevel,
                int steps, float thickness, 
                float2 rayCastSize, float3 rayStart, float3 rayDir)
{
    // float sampleSize = GetMarchSize(rayStart.xy, rayStart.xy + rayDir.xy, rayCastSize);
    // float3 samplePos = rayStart + rayDir * (sampleSize);
    // int level = hizStartLevel;
    // float mask = 0.0;

    // [loop]
    // for (int i = 0; i < steps; i++)
    // {
    //     float2 cellCount = rayCastSize * exp2(level + 1.0);
    //     float newSamplerSize = GetMarchSize(samplePos.xy, samplePos.xy + rayDir.xy, cellCount);
    //     float3 newSamplePos = samplePos + rayDir * newSamplerSize;
    //     float sampleMinDepth = SceneDepth.SampleLevel(SceneDepth_Sampler, newSamplePos.xy, level).r;
    //     // float sampleMinDepth = Texture2DSampleLevel(SceneDepth, SceneDepth_Sampler, newSamplePos.xy, level);

    //     [flatten]
    //     if (sampleMinDepth < newSamplePos.z)
    //     {
    //         level = min(HiZ_Max_Level, level + 1.0);
    //         samplePos = newSamplePos;
    //     }
    //     else
    //     {
    //         level--;
    //     }

    //     [branch]
    //     if (level < hizStopLevel)
    //     {
    //         float delta = (-LinearEyeDepth(sampleMinDepth)) - (-LinearEyeDepth(samplePos.z));
    //         mask = delta <= thickness && i > 0.0;
    //         return float4(samplePos, mask);
    //     }
    // }
    // return float4(samplePos, mask);
    return float4(0.0, 0.0, 0.0, 0.0);
}


float GetStepScreenFactorToClipAtScreenEdge(float2 RayStartScreen, float2 RayStepScreen)
{
	const float RayStepScreenInvFactor = 0.5 * length(RayStepScreen);
	const float2 S = 1 - max(abs(RayStepScreen + RayStartScreen * RayStepScreenInvFactor) - RayStepScreenInvFactor, 0.0f) / abs(RayStepScreen);
	const float RayStepFactor = min(S.x, S.y) / RayStepScreenInvFactor;
	return RayStepFactor;
}