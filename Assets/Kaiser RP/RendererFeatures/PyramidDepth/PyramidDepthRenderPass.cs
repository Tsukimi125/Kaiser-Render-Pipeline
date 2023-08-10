using System.Collections;
using System.Collections.Generic;
using UnityEngine;
using Unity.Mathematics;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

public class PyramidDepthRenderPass : ScriptableRenderPass
{
    public static class PyramidDepthShaderIDs
    {
        public static int HierarchicalDepth = Shader.PropertyToID("_SSR_HierarchicalDepth_RT");
        public static int Target = Shader.PropertyToID("_SSR_Target");
        public static int PrevCurr_InvSize = Shader.PropertyToID("_PrevCurr_Inverse_Size");
    }

    private PyramidDepthSettings settings; //基本参数
    private int[] pyramidMipIDs;
    int pyramidDepth_ID = Shader.PropertyToID("_PyramidDepth");
    int pyramidDepth_BackUp_ID = Shader.PropertyToID("_PyramidDepth_BackUp");

    private RenderTexture pyramidDepthRT;
    public PyramidDepthRenderPass(PyramidDepthSettings settings)
    {
        this.settings = settings;
        this.renderPassEvent = RenderPassEvent.BeforeRenderingOpaques;
        profilingSampler = new ProfilingSampler("[Kaiser] Pyramid Depth");

        pyramidMipIDs = new int[settings.mipCount];
        for (int i = 0; i < settings.mipCount; ++i)
        {
            pyramidMipIDs[i] = Shader.PropertyToID("_SSR_DepthMip_" + i);
        }
    }

    public override void Configure(CommandBuffer cmd, RenderTextureDescriptor cameraTextureDescriptor)
    {
        ConfigureInput(ScriptableRenderPassInput.Depth | ScriptableRenderPassInput.Normal);
    }

    public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
    {
        var cmd = CommandBufferPool.Get();

        using (new ProfilingScope(cmd, profilingSampler))
        {
            int2 bufferSize = new int2(renderingData.cameraData.cameraTargetDescriptor.width, renderingData.cameraData.cameraTargetDescriptor.height);

            RenderTextureDescriptor descriptor = new RenderTextureDescriptor((int)bufferSize.x, (int)bufferSize.y, 0)
            {
                colorFormat = RenderTextureFormat.RFloat,
                sRGB = false,
                useMipMap = true,
                autoGenerateMips = false
            };

            cmd.GetTemporaryRT(pyramidDepth_ID, descriptor);

            cmd.Blit(renderingData.cameraData.renderer.cameraDepthTargetHandle, pyramidDepth_ID);

            int2 mipSize = bufferSize;
            for (int i = 0; i < settings.mipCount; ++i)
            {
                mipSize.x /= 2;
                mipSize.y /= 2;

                if (mipSize.x < 1 || mipSize.y < 1)
                {
                    break;
                }

                cmd.GetTemporaryRT(pyramidMipIDs[i], mipSize.x, mipSize.y, 0, FilterMode.Point, RenderTextureFormat.RFloat, RenderTextureReadWrite.Default, 1, true);
                cmd.SetComputeIntParam(settings.computeShader, "_SampleLevel", i);
                cmd.SetComputeVectorParam(settings.computeShader, "_InvBufferSize", new float4(1.0f / mipSize.x, 1.0f / mipSize.y, 0.0f, 0.0f));

                cmd.SetComputeTextureParam(settings.computeShader, 0, "_SSR_HierarchicalDepth_RT", pyramidDepth_ID);
                cmd.SetComputeTextureParam(settings.computeShader, 0, "_SSR_Target", pyramidMipIDs[i]);
                cmd.DispatchCompute(settings.computeShader, 0, bufferSize.x / 8, bufferSize.y / 8, 1);
                cmd.CopyTexture(pyramidMipIDs[i], 0, 0, pyramidDepth_ID, 0, i + 1);
            }

            if (settings.debugEnabled)
            {
                cmd.Blit(pyramidDepth_ID, colorAttachmentHandle);
            }

            for (int j = 0; j < settings.mipCount; ++j)
            {
                cmd.ReleaseTemporaryRT(pyramidMipIDs[j]);
            }
        }
        context.ExecuteCommandBuffer(cmd);
        CommandBufferPool.Release(cmd);
    }
}