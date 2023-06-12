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
        public static int PrevMipDepth = Shader.PropertyToID("_PrevMipDepth");
        public static int HierarchicalDepth = Shader.PropertyToID("_HierarchicalDepth");
        public static int PrevCurr_InvSize = Shader.PropertyToID("_PrevCurr_Inverse_Size");
    }

    private PyramidDepthSettings settings; //基本参数
    private int[] pyramidMipIDs;

    private RenderTexture pyramidDepthRT;
    public PyramidDepthRenderPass(PyramidDepthSettings settings)
    {
        this.settings = settings;
        // if (settings.debugEnabled)
        // {
        //     this.renderPassEvent = RenderPassEvent.AfterRendering;
        // }
        // else
        // {

        // }
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
            int2 lastBufferSize = bufferSize;

            RenderTextureDescriptor descriptor = new RenderTextureDescriptor((int)bufferSize.x, (int)bufferSize.y, 0);
            descriptor.colorFormat = RenderTextureFormat.RFloat;
            descriptor.sRGB = false;
            descriptor.useMipMap = true;
            descriptor.autoGenerateMips = true;
            RenderTexture.ReleaseTemporary(pyramidDepthRT);
            pyramidDepthRT = RenderTexture.GetTemporary(descriptor);

            cmd.Blit(renderingData.cameraData.renderer.cameraDepthTargetHandle, pyramidDepthRT);

            RenderTargetIdentifier pyramidDepthTexture = new RenderTargetIdentifier(pyramidDepthRT);
            RenderTargetIdentifier lastPyramidDepthTexture = pyramidDepthRT;

            for (int i = 0; i < settings.mipCount; ++i)
            {
                bufferSize.x /= 2;
                bufferSize.y /= 2;

                int dispatchSizeX = Mathf.CeilToInt(bufferSize.x / 8);
                int dispatchSizeY = Mathf.CeilToInt(bufferSize.y / 8);
                if (dispatchSizeX < 1 || dispatchSizeY < 1) break;

                cmd.GetTemporaryRT(pyramidMipIDs[i], bufferSize.x, bufferSize.y, 0, FilterMode.Point, RenderTextureFormat.RFloat, RenderTextureReadWrite.Default, 1, true);
                cmd.SetComputeVectorParam(settings.computeShader, PyramidDepthShaderIDs.PrevCurr_InvSize, new float4(1.0f / bufferSize.x, 1.0f / bufferSize.y, 1.0f / lastBufferSize.x, 1.0f / lastBufferSize.y));
                cmd.SetComputeTextureParam(settings.computeShader, 0, PyramidDepthShaderIDs.PrevMipDepth, lastPyramidDepthTexture);
                cmd.SetComputeTextureParam(settings.computeShader, 0, PyramidDepthShaderIDs.HierarchicalDepth, pyramidMipIDs[i]);
                cmd.DispatchCompute(settings.computeShader, 0, dispatchSizeX, dispatchSizeY, 1);
                cmd.CopyTexture(pyramidMipIDs[i], 0, 0, pyramidDepthTexture, 0, i + 1);

                lastBufferSize = bufferSize;
                lastPyramidDepthTexture = pyramidMipIDs[i];

                if (settings.debugEnabled)
                {
                    cmd.Blit(lastPyramidDepthTexture, colorAttachmentHandle);
                }




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