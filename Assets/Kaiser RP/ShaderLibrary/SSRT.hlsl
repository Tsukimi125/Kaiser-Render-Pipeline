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

float3 GetViewSpacePosition(float3 screenPos)
{
    half4 viewPos = mul(UNITY_MATRIX_I_P, half4(screenPos, 1));
    return viewPos.xyz / viewPos.w;
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


float3 intersectDepthPlane(float3 rayOrigin, float3 rayDir, float marchSize) {
    //march size is a funtion of Hiz buffer
    return rayOrigin + rayDir * marchSize;
}

//returns the 2D integer index of the cell that contains the given 2D position within it
float2 cell(float2 ray, float2 cellCount) {
    return floor(ray * cellCount);
}

//cell count is just the resolution of the Hiz texture at the specific mip level 
float2 cellCount(float mipLevel, float2 bufferSize) {
    return bufferSize / (mipLevel == 0 ? 1 : exp2(mipLevel));
}

float3 intersectCellBoundary(float3 rayOrigin, float3 rayDir, float2 cellIndex, float2 cellCount, float2 crossStep, float2 crossOffset) {
    //by dividing the cell index by cell count, we can get the position of the boundaries between the current cell and the new cell
    float2 cellSize = 1.0 / cellCount;
    //crossStep is added to the current cell to get the next cell index, crossOffset is used to push the position just a tiny bit further to make sure the new position is not right on the boundary
    float2 planes = cellIndex / cellCount + cellSize * crossStep;
    //the delta between the new position and the origin is calculated. The delta is divided by xy component of d vector, after division, the x and y component in delta will have value between 0 to 1 which represents how far the delta position is from the origin of the ray
    float2 solutions = (planes - rayOrigin) / rayDir.xy;
    float3 intersectionPos = intersectDepthPlane(rayOrigin, rayDir, min(solutions.x, solutions.y));
    intersectionPos.xy += (solutions.x < solutions.y) ? float2(crossOffset.x, 0.0) : float2(0.0, crossOffset.y);
    return intersectionPos;
}

//if the new id is different from the old id ,we know we crossed a cell
bool crossedCellBoundary(float2 cellIdOne, float2 cellIdTwo) {
    return (int)cellIdOne.x != (int)cellIdTwo.x || (int)cellIdOne.y != (int)cellIdTwo.y;
}

float minimumDepthPlane(float2 ray, float mipLevel, float2 cellCount, Texture2D SceneDepth) {
    return -SceneDepth.Load(int3((ray * cellCount), mipLevel));
}

float4 HizTrace_Advanced(int HizMaxLevel, int HizStartLevel, int HizStopLevel, 
    int numSteps, float thickness, bool traceBehind, 
    float threshold, float2 bufferSize, 
    float3 rayOrigin, float3 rayDir, Texture2D sceneDepth
) 
{
    HizMaxLevel = clamp(HizMaxLevel, 0, 7);
    rayOrigin.z *= -1;
    rayDir.z *= -1;
    float mipLevel = HizStartLevel;
    float3 ray = rayOrigin;
    //get the cell cross direction and a small offset to enter the next cell when doing cell cross
    float2 crossStep = float2(rayDir.x >= 0.0 ? 1.0 : -1.0, rayDir.y >= 0.0 ? 1.0 : -1.0);
    float2 crossOffset = crossStep * 0.00001;
    crossStep = saturate(crossStep);
    float2 HizSize = cellCount(mipLevel, bufferSize);
    //cross to next cell so that we don't get a self-intersection immediately
    float2 rayCell = cell(ray.xy, HizSize);
    ray = intersectCellBoundary(ray, rayDir, rayCell, HizSize, crossStep, crossOffset);
    int iterations = 0;
    float mask = 1.0;
    while (mipLevel >= HizStopLevel && iterations < numSteps) {
        float3 tempRay = ray;
        //get the cell number of the current ray
        float2 currentCellCount = cellCount(mipLevel, bufferSize);
        float2 oldCellId = cell(ray.xy, currentCellCount);
        //get the minimum depth plane in which the current ray
        float minZ = minimumDepthPlane(ray.xy, mipLevel, currentCellCount, sceneDepth);
        if (rayDir.z > 0) {
            //compare min ray with current ray pos
            float minMinusRay = minZ - ray.z;
            tempRay = minMinusRay > 0 ? ray + (rayDir / rayDir.z) * minMinusRay : tempRay;
            float2 newCellId = cell(tempRay, currentCellCount);
            if (crossedCellBoundary(oldCellId, newCellId)) {
                //so intersect the boundary of that cell instead, and go up a level for taking a larger step next loop
                tempRay = intersectCellBoundary(ray, rayDir, oldCellId, currentCellCount, crossStep, crossOffset);
                mipLevel = min(HizMaxLevel, mipLevel + 2.0);
            } else {
                if (mipLevel == HizStartLevel && abs(minMinusRay) > threshold && traceBehind) {
                    //https://www.jpgrenier.org/ssr.html, trace behind cost pretty much sometimes degenerate into linear search
                    tempRay = intersectCellBoundary(ray, rayDir, oldCellId, currentCellCount, crossStep, crossOffset);
                    mipLevel = HizStartLevel + 1;
                }
            }
        }
        else if (ray.z < minZ) {
            tempRay = intersectCellBoundary(ray, rayDir, oldCellId, currentCellCount, crossStep, crossOffset);
            mipLevel = min(HizMaxLevel, mipLevel + 2.0);
        }
        ray = tempRay;
        //go down a level in Hiz
        mipLevel--;
        iterations++;
        mask = (-LinearEyeDepth(-minZ, _ZBufferParams)) - (-LinearEyeDepth(-ray.z, _ZBufferParams)) < thickness && iterations > 0.0;
    }
    return float4(ray.xy, -ray.z, mask);
}


float GetStepScreenFactorToClipAtScreenEdge(float2 RayStartScreen, float2 RayStepScreen)
{
	const float RayStepScreenInvFactor = 0.5 * length(RayStepScreen);
	const float2 S = 1 - max(abs(RayStepScreen + RayStartScreen * RayStepScreenInvFactor) - RayStepScreenInvFactor, 0.0f) / abs(RayStepScreen);
	const float RayStepFactor = min(S.x, S.y) / RayStepScreenInvFactor;
	return RayStepFactor;
}

#endif