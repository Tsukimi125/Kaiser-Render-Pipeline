#ifndef KAISER_HIZ_TRACE
#define KAISER_HIZ_TRACE 

float2 getScaledResolution(int index, float2 resolution)
{
    float scale = exp2(index);
    float2 scaledScreen = resolution / scale;
    //scaledScreen.xy = max(floor(scaledScreen.xy), float2(1,1));
    return scaledScreen.xy;
}

inline float2 scaledUv(float2 uv, int index, float2 resolution)
{
    float2 scaledScreen = getScaledResolution(index, resolution);
    float2 realScale = scaledScreen.xy / resolution;
    uv *= realScale;
    return uv;
}
inline float SampleDepth(float2 uv, int index, Texture2D _DepthPyramid, SamplerState sampler_DepthPyramid, float2 resolution)
{
    uv = scaledUv(uv, index, resolution);
    return _DepthPyramid.SampleLevel(sampler_DepthPyramid, uv, index);
    // return UNITY_SAMPLE_TEX2DARRAY(_DepthPyramid, float3(uv, index));
}
inline float2 cross_epsilon(float2 resolution)
{
    //float2 scale = _ScreenParams.xy / getResolution(HIZ_START_LEVEL + 1);
    //return float2(_MainTex_TexelSize.xy * scale);
    return float2(1 / resolution / 128);
}
inline float2 cell(float2 ray, float2 cell_count)
{
    return floor(ray.xy * cell_count);
}
inline float2 cell_count(float level, float2 resolution)
{
    float2 res = getScaledResolution(level, resolution);
    return res; //_ScreenParams.xy / exp2(level);

}
inline bool crossed_cell_boundary(float2 cell_id_one, float2 cell_id_two)
{
    return (int)cell_id_one.x != (int)cell_id_two.x || (int)cell_id_one.y != (int)cell_id_two.y;
}
inline float minimum_depth_plane(float2 ray, float level, float2 cell_count, Texture2D _DepthPyramid, SamplerState sampler_DepthPyramid, float2 resolution)
{
    return SampleDepth(ray, level, _DepthPyramid, sampler_DepthPyramid, resolution);
}
inline float3 intersectDepthPlane(float3 o, float3 d, float t)
{
    return o + d * t;
}
inline float3 intersectCellBoundary(float3 o, float3 d, float2 cellIndex, float2 cellCount, float2 crossStep, float2 crossOffset, float iteration)
{
    float2 cell_size = 1.0 / cellCount;
    float2 planes = cellIndex / cellCount + cell_size * crossStep;
    float2 solutions = (planes - o) / d.xy;
    float3 intersection_pos = o + d * min(solutions.x, solutions.y);
    
    //magic scale, it helps with some artifacts
    crossOffset.xy *= 16;

    intersection_pos.xy += (solutions.x < solutions.y) ? float2(crossOffset.x, 0.0) : float2(0.0, crossOffset.y);
    return intersection_pos;

    //float2 cell_size = 1.0 / cellCount;
    //float2 planes = cellIndex / cellCount + cell_size * crossStep + crossOffset * 50;
    //float2 solutions = (planes - o.xy) / d.xy;
    //float3 intersection_pos = o + d * min(solutions.x, solutions.y);
    //return intersection_pos;

}


float3 hiZTrace(int HiZ_Max_Level, int HiZ_Start_Level, int HiZ_Stop_Level, 
    float3 p, float3 v, float MaxIterations, float2 resolution, 
    Texture2D _DepthPyramid, SamplerState sampler_DepthPyramid, bool reflectSky,
    out bool hit, out bool isSky)
{
    const float rootLevel = HiZ_Max_Level;
    float level = HiZ_Start_Level;

    int iterations = 0;
    isSky = false;
    hit = 0;

    [branch]
    if (v.z <= 0)
    {
        return float3(0, 0, 0);
    }

    // scale vector such that z is 1.0f (maximum depth)
    float3 d = v.xyz / v.z;

    // get the cell cross direction and a small offset to enter the next cell when doing cell crossing
    float2 crossStep = float2(d.x >= 0.0f ? 1.0f : - 1.0f, d.y >= 0.0f ? 1.0f : - 1.0f);
    float2 crossOffset = float2(crossStep.xy * cross_epsilon(resolution));
    crossStep.xy = saturate(crossStep.xy);

    // set current ray to original screen coordinate and depth
    float3 ray = p.xyz;

    // cross to next cell to avoid immediate self-intersection
    float2 rayCell = cell(ray.xy, cell_count(level, resolution));

    ray = intersectCellBoundary(ray, d, rayCell.xy, cell_count(level, resolution), crossStep.xy, crossOffset.xy, 0);

    [loop]
    while (level >= HiZ_Stop_Level && iterations < MaxIterations)
    {
        // get the cell number of the current ray
        const float2 cellCount = cell_count(level, resolution);
        const float2 oldCellIdx = cell(ray.xy, cellCount);

        // get the minimum depth plane in which the current ray resides
        float minZ = minimum_depth_plane(ray.xy, level, rootLevel, _DepthPyramid, sampler_DepthPyramid, resolution);

        // intersect only if ray depth is below the minimum depth plane
        float3 tmpRay = ray;

        float min_minus_ray = minZ - ray.z;

        tmpRay = min_minus_ray > 0 ? intersectDepthPlane(tmpRay, d, min_minus_ray) : tmpRay;
        // get the new cell number as well
        const float2 newCellIdx = cell(tmpRay.xy, cellCount);
        // if the new cell number is different from the old cell number, a cell was crossed
        [branch]
        if (crossed_cell_boundary(oldCellIdx, newCellIdx))
        {
            // intersect the boundary of that cell instead, and go up a level for taking a larger step next iteration
            tmpRay = intersectCellBoundary(ray, d, oldCellIdx, cellCount.xy, crossStep.xy, crossOffset.xy, iterations); //// NOTE added .xy to o and d arguments
            level = min(HiZ_Max_Level, level + 2.0f);
        }
        else if (level == HiZ_Start_Level)
        {
            float minZOffset = (minZ + (_ProjectionParams.y * 0.0025) / LinearEyeDepth(1 - p.z, _ZBufferParams));

            isSky = minZ == 1 ? true : false;

            [branch]
            if (tmpRay.z > minZOffset || (reflectSky == 0 && isSky))
            {
                break;
            }
        }
        // go down a level in the hi-z buffer
        --level;

        ray.xyz = tmpRay.xyz;
        ++iterations;
    }
    hit = level < HiZ_Stop_Level ? 1 : 0;
    return ray;
}



#endif