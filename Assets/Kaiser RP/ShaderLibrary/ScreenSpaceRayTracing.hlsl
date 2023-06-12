#ifndef KAISER_SCREEN_SPACE_RAY_TRACING
#define KAISER_SCREEN_SPACE_RAY_TRACING

#include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Common.hlsl"


#define RAY_BIAS 0.05f


float3 GetScreenPos(float2 uv, float depth)
{
    //return float3(uv.xy * 2 - 1, depth);
    return float3(uv.x * 2.0f - 1.0f, 2.0f * uv.y - 1, depth);
}

float3 ReconstructWorldPos(float2 uv, float depth)
{
    float ndcX = uv.x * 2 - 1;
    float ndcY = uv.y * 2 - 1; // Remember to flip y!!!
    float4 viewPos = mul(UNITY_MATRIX_I_P, float4(ndcX, ndcY, depth, 1.0f));
    viewPos = viewPos / viewPos.w;
    return mul(UNITY_MATRIX_I_V, viewPos).xyz;
}

float3 GetViewDir(float3 worldPos)
{
    return normalize(worldPos - GetCameraPositionWS());
}

float3 GetViewPos(float3 screenPos)
{
    float4 viewPos = mul(UNITY_MATRIX_I_P, float4(screenPos, 1));
    return viewPos.xyz / viewPos.w;
}

float4 TangentToWorld(float3 N, float4 H)
{
    float3 UpVector = abs(N.y) < 0.999 ? float3(0.0, 1.0, 0.0) : float3(1.0, 0.0, 0.0);
    float3 T = normalize(cross(UpVector, N));
    float3 B = cross(N, T);

    return float4((T * H.x) + (B * H.y) + (N * H.z), H.w);
}

// Brian Karis, Epic Games "Real Shading in Unreal Engine 4"
float4 ImportanceSampleGGX(float2 Xi, float Roughness)
{
    float m = Roughness * Roughness;
    float m2 = m * m;

    float Phi = 2 * PI * Xi.x;

    float CosTheta = sqrt((1.0 - Xi.y) / (1.0 + (m2 - 1.0) * Xi.y));
    float SinTheta = sqrt(max(1e-5, 1.0 - CosTheta * CosTheta));

    float3 H;
    H.x = SinTheta * cos(Phi);
    H.y = SinTheta * sin(Phi);
    H.z = CosTheta;

    float d = (CosTheta * m2 - CosTheta) * CosTheta + 1;
    float D = m2 / (PI * d * d);
    float pdf = D * CosTheta;

    return float4(H, pdf);
}


float3 intersectDepth_Plane(float3 rayOrigin, float3 rayDir, float marchSize)
{
    return rayOrigin + rayDir * marchSize;
}

float2 cell2(float2 ray, float2 cell_count)
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

float minimum_depth_plane(float2 ray, float level, float2 cell_count, Texture2D hiz_texture)
{
    // return hiz_texture[max((int)level, 0)].Load(int3((ray * cell_count), 0)).r;
    return hiz_texture.Load(int3((ray * cell_count), level)).r;
}

float4 Hierarchical_Z_Trace(int HiZ_Max_Level, int HiZ_Start_Level, int HiZ_Stop_Level, int NumSteps, float Thickness, float2 screenSize, float3 rayOrigin, float3 rayDir, Texture2D HiZ_texture)
{
    HiZ_Max_Level = clamp(HiZ_Max_Level, 0, 7);
    rayOrigin = half3(rayOrigin.x, rayOrigin.y, rayOrigin.z);
    rayDir = half3(rayDir.x, rayDir.y, rayDir.z);

    float level = HiZ_Start_Level;
    float3 ray = rayOrigin + rayDir * RAY_BIAS;

    float2 cross_step = float2(rayDir.x >= 0.0 ? 1.0 : - 1.0, rayDir.y >= 0.0 ? 1.0 : - 1.0);
    float2 cross_offset = cross_step * 0.00001f;
    cross_step = saturate(cross_step);

    float2 hi_z_size = cell_count(level, screenSize);
    //ray.xy = floor(ray.xy * hi_z_size) / hi_z_size + 0.50f / hi_z_size;
    float2 ray_cell = cell2(ray.xy, hi_z_size.xy);
    ray = intersect_cell_boundary(ray, rayDir, ray_cell, hi_z_size, cross_step, cross_offset);

    int iterations = 0;
    float mask = 1.0f;
    while (level >= HiZ_Stop_Level && iterations < NumSteps)
    {
        float3 tmp_ray = ray;
        float2 current_cell_count = cell_count(level, screenSize);
        float2 old_cell_id = cell2(ray.xy, current_cell_count);

        if (ray.x < 0.0f ||
        ray.x > 1.0f ||
        ray.y < 0.0f ||
        ray.y > 1.0f
        )
        {
            mask = 0.0f;
            return half4(ray.xy, ray.z, mask);
        }

        float min_z = minimum_depth_plane(ray.xy, level, current_cell_count, HiZ_texture);

        if (min_z < 1e-7)
        {
            mask = 0.0f;
            return half4(ray.xy, ray.z, mask);
        }

        if (rayDir.z < 0)
        {
            float min_minus_ray = min_z - ray.z;
            tmp_ray = min_minus_ray < 0 ? ray + (rayDir / rayDir.z) * min_minus_ray : tmp_ray;
            float2 new_cell_id = cell2(tmp_ray.xy, current_cell_count);

            if (crossed_cell_boundary(old_cell_id, new_cell_id))
            {
                tmp_ray = intersect_cell_boundary(ray, rayDir, old_cell_id, current_cell_count, cross_step, cross_offset);
                level = min(HiZ_Max_Level, level + 2.0);
            }
            else
            {
                if (level == 1.0 && abs(min_minus_ray) > 0.0001)
                {
                    tmp_ray = intersect_cell_boundary(ray, rayDir, old_cell_id, current_cell_count, cross_step, cross_offset);
                    level = 2.0;
                }
            }
        }
        else if (ray.z > min_z)
        {
            tmp_ray = intersect_cell_boundary(ray, rayDir, old_cell_id, current_cell_count, cross_step, cross_offset);
            level = min(HiZ_Max_Level, level + 2.0);
        }

        ray.xyz = tmp_ray.xyz;
        level--;
        iterations++;

        mask = (LinearEyeDepth(ray.z, _ZBufferParams) - LinearEyeDepth(min_z, _ZBufferParams)) < Thickness && iterations > 0.0;
    }

    return half4(ray.xy, ray.z, mask);
}

#endif