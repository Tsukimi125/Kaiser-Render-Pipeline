#ifndef KAISER_SCREEN_SPACE_RAY_TRACING
#define KAISER_SCREEN_SPACE_RAY_TRACING

#include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Common.hlsl"
#include "KaiserStandard.hlsl"

#define RAY_BIAS 0.05f

float3x3 GetTangentBasis(float3 TangentZ)
{
    float3 UpVector = abs(TangentZ.z) < 0.999 ? float3(0, 0, 1) : float3(1, 0, 0);
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

float3 intersectDepth_Plane(float3 rayOrigin, float3 rayDir, float marchSize)
{
    return rayOrigin + rayDir * marchSize;
}

float2 cell(float2 ray, float2 cell_count)
{
    return floor(ray.xy * cell_count);
}

float2 cell_count(float level, float2 ScreenSize)
{
    return ScreenSize / (level == 0 ? 1 : exp2(level));
}

float3 intersect_cell_boundary(float3 rayOrigin, float3 rayDir, float2 cellIndex, float2 cellCount, float2 crossStep, float2 crossOffset)
{
    float2 cell_size = 1.0 / cellCount;
    float2 planes = cellIndex / cellCount + cell_size * crossStep;

    float2 solutions = (planes - rayOrigin.xy) / rayDir.xy;
    float3 intersection_pos = rayOrigin + rayDir * min(solutions.x, solutions.y);

    intersection_pos.xy += (solutions.x < solutions.y) ? float2(crossOffset.x, 0.0) : float2(0.0, crossOffset.y);

    return intersection_pos;
}

bool crossed_cell_boundary(float2 cell_id_one, float2 cell_id_two)
{
    return (int)cell_id_one.x != (int)cell_id_two.x || (int)cell_id_one.y != (int)cell_id_two.y;
}

float minimum_depth_plane(float2 ray, float level, float2 cell_count, Texture2D SceneDepth)
{
    return -SceneDepth.Load(float3(ray * cell_count, level)).r;
}

float4 Hierarchical_Z_Trace(int HiZ_Max_Level, int HiZ_Start_Level, int HiZ_Stop_Level, int NumSteps, float Thickness, float2 screenSize, float3 rayOrigin, float3 rayDir, Texture2D SceneDepth)
{
    HiZ_Max_Level = clamp(HiZ_Max_Level, 0.0, 7.0);
    rayOrigin = half3(rayOrigin.x, rayOrigin.y, -rayOrigin.z); rayDir = half3(rayDir.x, rayDir.y, -rayDir.z);

    float level = HiZ_Start_Level; float3 ray = rayOrigin;

    float2 cross_step = float2(rayDir.x >= 0.0 ? 1.0 : - 1.0, rayDir.y >= 0.0 ? 1.0 : - 1.0);
    float2 cross_offset = cross_step * 0.00001;
    cross_step = saturate(cross_step);

    float2 hi_z_size = cell_count(level, screenSize);
    float2 ray_cell = cell(ray.xy, hi_z_size.xy);
    ray = intersect_cell_boundary(ray, rayDir, ray_cell, hi_z_size, cross_step, cross_offset);

    int iterations = 0.0; float mask = 1.0;
    while (level >= HiZ_Stop_Level && iterations < NumSteps)
    {
        float3 tmp_ray = ray;
        float2 current_cell_count = cell_count(level, screenSize);
        float2 old_cell_id = cell(ray.xy, current_cell_count);
        float min_z = minimum_depth_plane(ray.xy, level, current_cell_count, SceneDepth);

        if (rayDir.z > 0)
        {
            float min_minus_ray = min_z - ray.z;
            tmp_ray = min_minus_ray > 0 ? ray + (rayDir / rayDir.z) * min_minus_ray : tmp_ray;
            float2 new_cell_id = cell(tmp_ray.xy, current_cell_count);
            
            if (crossed_cell_boundary(old_cell_id, new_cell_id))
            {
                tmp_ray = intersect_cell_boundary(ray, rayDir, old_cell_id, current_cell_count, cross_step, cross_offset);
                level = min(HiZ_Max_Level, level + 2.0);
            }
            /* else {
                    if(level == 1.0 && abs(min_minus_ray) > 0.0001) {
                        tmp_ray = intersect_cell_boundary(ray, rayDir, old_cell_id, current_cell_count, cross_step, cross_offset);
                        level = 2.0;
                    }
            }*/
        }
        else if (ray.z < min_z)
        {
            tmp_ray = intersect_cell_boundary(ray, rayDir, old_cell_id, current_cell_count, cross_step, cross_offset);
            level = min(HiZ_Max_Level, level + 2.0);
        }

        ray.xyz = tmp_ray.xyz;
        level--;
        iterations++;

        mask = (-LinearEyeDepth(-min_z, _ZBufferParams)) - (-LinearEyeDepth(-ray.z, _ZBufferParams)) < Thickness && iterations > 0.0;
    }

    return half4(ray.xy, -ray.z, mask);
}

float GetEdgeStoppNormalWeight(float3 normal_p, float3 normal_q, float sigma)
{
    return pow(max(dot(normal_p, normal_q), 0.0), sigma);
}

float GetEdgeStopDepthWeight(float x, float m, float sigma)
{
    float a = length(x - m) / sigma;
    a *= a;
    return exp(-0.5 * a);
}



/*********************/

float GetStepScreenFactorToClipAtScreenEdge(float2 RayStartScreen, float2 RayStepScreen)
{
    const float RayStepScreenInvFactor = 0.5 * length(RayStepScreen);
    const float2 S = 1 - max(abs(RayStepScreen + RayStartScreen * RayStepScreenInvFactor) - RayStepScreenInvFactor, 0.0f) / abs(RayStepScreen);
    const float RayStepFactor = min(S.x, S.y) / RayStepScreenInvFactor;
    return RayStepFactor;
}

float GetScreenFadeBord(float2 pos, float value)
{
    float borderDist = min(1 - max(pos.x, pos.y), min(pos.x, pos.y));
    return saturate(borderDist > value ? 1 : borderDist / value);
}

bool RayCast_Specular(
    uint NumSteps, float Roughness, float CompareFactory, float StepOffset,
    float3 RayStartScreen, float3 RayStepScreen,
    Texture2D Texture, SamplerState TextureSampler,
    out float3 OutHitUVz, out float Level)
{
    float Step = 1.0 / NumSteps;
    float CompareTolerance = CompareFactory * Step;

    float3 RayStartUVz = float3((RayStartScreen.xy * float2(0.5, 0.5) + 0.5), RayStartScreen.z);
    float3 RayStepUVz = float3(RayStepScreen.xy * float2(0.5, 0.5), RayStepScreen.z);
    RayStepUVz *= Step;
    float3 RayUVz = RayStartUVz + RayStepUVz * StepOffset;
    
    Level = 1;
    bool bHit = false;
    float LastDiff = 0;
    OutHitUVz = float3(0, 0, 0);

    [unroll(12)]
    for (uint i = 0; i < NumSteps; i += 4)
    {
        // Vectorized to group fetches
        float4 SampleUV0 = RayUVz.xyxy + RayStepUVz.xyxy * float4(1, 1, 2, 2);
        float4 SampleUV1 = RayUVz.xyxy + RayStepUVz.xyxy * float4(3, 3, 4, 4);
        float4 SampleZ = RayUVz.zzzz + RayStepUVz.zzzz * float4(1, 2, 3, 4);
        
        // Use lower res for farther samples
        float4 SampleDepth;
        SampleDepth.x = Texture.SampleLevel(TextureSampler, (SampleUV0.xy), 0).r;
        SampleDepth.y = Texture.SampleLevel(TextureSampler, (SampleUV0.zw), 0).r;
        Level += (8.0 / NumSteps) * Roughness;
        
        SampleDepth.z = Texture.SampleLevel(TextureSampler, (SampleUV1.xy), 0).r;
        SampleDepth.w = Texture.SampleLevel(TextureSampler, (SampleUV1.zw), 0).r;
        Level += (8.0 / NumSteps) * Roughness;

        float4 DepthDiff = SampleZ - SampleDepth;
        bool4 Hit = abs(DepthDiff + CompareTolerance) < CompareTolerance;

        [branch]
        if (any(Hit))
        {
            float DepthDiff0 = DepthDiff[2];
            float DepthDiff1 = DepthDiff[3];
            float Time0 = 3;

            [flatten]
            if (Hit[2])
            {
                DepthDiff0 = DepthDiff[1];
                DepthDiff1 = DepthDiff[2];
                Time0 = 2;
            }
            [flatten]
            if (Hit[1])
            {
                DepthDiff0 = DepthDiff[0];
                DepthDiff1 = DepthDiff[1];
                Time0 = 1;
            }
            [flatten]
            if (Hit[0])
            {
                DepthDiff0 = LastDiff;
                DepthDiff1 = DepthDiff[0];
                Time0 = 0;
            }

            float Time1 = Time0 + 1;
            #if 1
                // Binary search
                for (uint j = 0; j < 4; j++)
                {
                    CompareTolerance *= 0.5;

                    float MidTime = 0.5 * (Time0 + Time1);
                    float3 MidUVz = RayUVz + RayStepUVz * MidTime;
                    float MidDepth = Texture.SampleLevel(TextureSampler, MidUVz.xy, Level).r;
                    float MidDepthDiff = MidUVz.z - MidDepth;

                    if (abs(MidDepthDiff + CompareTolerance) < CompareTolerance)
                    {
                        DepthDiff1 = MidDepthDiff;
                        Time1 = MidTime;
                    }
                    else
                    {
                        DepthDiff0 = MidDepthDiff;
                        Time0 = MidTime;
                    }
                }
            #endif
            float TimeLerp = saturate(DepthDiff0 / (DepthDiff0 - DepthDiff1));
            float IntersectTime = Time0 + TimeLerp;
            OutHitUVz = RayUVz + RayStepUVz * IntersectTime;

            bHit = true;
            break;
        }
        LastDiff = DepthDiff.w;
        RayUVz += 4 * RayStepUVz;
    }

    return bHit;
}

#endif