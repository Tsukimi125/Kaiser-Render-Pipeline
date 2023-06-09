#ifndef KAISER_SSR_INCLUDED
#define KAISER_SSR_INCLUDED

#include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Common.hlsl"

int _SSR_HiZ_PrevDepthLevel;
TEXTURE2D_X(_SSR_HierarchicalDepth_RT);
SAMPLER(sampler_point_clamp);

struct Varyings {
	float4 positionCS : SV_POSITION;
	float2 screenUV : VAR_SCREEN_UV;
};

Varyings DefaultPassVertex(uint vertexID : SV_VertexID) {
	Varyings output;
	//make the [-1, 1] NDC, visible UV coordinates cover the 0-1 range
	output.positionCS = float4(vertexID <= 1 ? -1.0 : 3.0,
		vertexID == 1 ? 3.0 : -1.0,
		0.0, 1.0);
	output.screenUV = float2(vertexID <= 1 ? 0.0 : 2.0,
		vertexID == 1 ? 2.0 : 0.0);
	//some graphics APIs have the texture V coordinate start at the top while others have it start at the bottom
	if (_ProjectionParams.x < 0.0) {
		output.screenUV.y = 1.0 - output.screenUV.y;
	}
	// output.screenUV.y = 1.0 - output.screenUV.y;
	return output;
}

//get Hierarchical ZBuffer
float GetHierarchicalZBuffer(Varyings input) : SV_TARGET{
	float2 uv = input.screenUV;
	float4 minDepth = float4(
		_SSR_HierarchicalDepth_RT.SampleLevel(sampler_point_clamp, uv, _SSR_HiZ_PrevDepthLevel, int2(-1.0, -1.0)).r,
		_SSR_HierarchicalDepth_RT.SampleLevel(sampler_point_clamp, uv, _SSR_HiZ_PrevDepthLevel, int2(-1.0, 1.0)).r,
		_SSR_HierarchicalDepth_RT.SampleLevel(sampler_point_clamp, uv, _SSR_HiZ_PrevDepthLevel, int2(1.0, -1.0)).r,
		_SSR_HierarchicalDepth_RT.SampleLevel(sampler_point_clamp, uv, _SSR_HiZ_PrevDepthLevel, int2(1.0, 1.0)).r
	);
	//sample pixel surrounds and pick minnset depth
	return max(max(minDepth.r, minDepth.g), max(minDepth.b, minDepth.a));
	// return 0.5;
}



#endif