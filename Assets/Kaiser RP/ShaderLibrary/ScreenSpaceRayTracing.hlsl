#ifndef KAISER_SCREEN_SPACE_RAY_TRACING
#define KAISER_SCREEN_SPACE_RAY_TRACING

#include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Common.hlsl"

#define RAY_BIAS 0.05f

float3x3 GetTangentBasis(float3 TangentZ) {
	float3 UpVector = abs(TangentZ.z) < 0.999 ? float3(0, 0, 1) : float3(1, 0, 0);
	float3 TangentX = normalize(cross( UpVector, TangentZ));
	float3 TangentY = cross(TangentZ, TangentX);
	return float3x3(TangentX, TangentY, TangentZ);
}

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
	float3 RayStepUVz  = float3(RayStepScreen.xy  * float2(0.5, 0.5), RayStepScreen.z);
	RayStepUVz *= Step;
	float3 RayUVz = RayStartUVz + RayStepUVz * StepOffset;
    
	Level = 1;
	bool bHit = false;
	float LastDiff = 0;
	OutHitUVz = float3(0, 0, 0);

	[unroll(12)]
	for( uint i = 0; i < NumSteps; i += 4 )
	{
		// Vectorized to group fetches
		float4 SampleUV0 = RayUVz.xyxy + RayStepUVz.xyxy * float4( 1, 1, 2, 2 );
		float4 SampleUV1 = RayUVz.xyxy + RayStepUVz.xyxy * float4( 3, 3, 4, 4 );
		float4 SampleZ   = RayUVz.zzzz + RayStepUVz.zzzz * float4( 1, 2, 3, 4 );
		
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
        if(any(Hit))
		{
			float DepthDiff0 = DepthDiff[2];
			float DepthDiff1 = DepthDiff[3];
			float Time0 = 3;

			[flatten]  
            if( Hit[2] ) {
				DepthDiff0 = DepthDiff[1];
				DepthDiff1 = DepthDiff[2];
				Time0 = 2;
			}
			[flatten] 
            if( Hit[1] ) {
				DepthDiff0 = DepthDiff[0];
				DepthDiff1 = DepthDiff[1];
				Time0 = 1;
			}
			[flatten] 
            if( Hit[0] ) {
				DepthDiff0 = LastDiff;
				DepthDiff1 = DepthDiff[0];
				Time0 = 0;
			}

			float Time1 = Time0 + 1;
		#if 0
			// Binary search
			for( uint j = 0; j < 4; j++ )
			{
				CompareTolerance *= 0.5;

				float  MidTime = 0.5 * ( Time0 + Time1 );
				float3 MidUVz = RayUVz + RayStepUVz * MidTime;
				float  MidDepth = Texture.SampleLevel( TextureSampler, MidUVz.xy, Level ).r;
				float  MidDepthDiff = MidUVz.z - MidDepth;

				if( abs( MidDepthDiff + CompareTolerance ) < CompareTolerance ) {
					DepthDiff1	= MidDepthDiff;
					Time1		= MidTime;
				} else {
					DepthDiff0	= MidDepthDiff;
					Time0		= MidTime;
				}
			}
		#endif
			float TimeLerp = saturate( DepthDiff0 / (DepthDiff0 - DepthDiff1) );
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