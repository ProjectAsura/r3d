﻿//-----------------------------------------------------------------------------
// File : TemporalResampling.hlsl
// Desc : Temporal Resampling.
// Copyright(c) Project Asura. All right reserved.
//-----------------------------------------------------------------------------

//-----------------------------------------------------------------------------
// Includes
//-----------------------------------------------------------------------------
#include <Reservoir.hlsli>
#include <Common.hlsli>

//-----------------------------------------------------------------------------
// Resources
//-----------------------------------------------------------------------------
RWStructuredBuffer<Reservoir>   TemporalReservoirBuffer : register(u0);
StructuredBuffer<Reservoir>     InitialSampleBuffer     : register(t4);


float CalcSourcePDF(Sample value)
{ return value.Pdf_v; }

float CalcTargetPDF(Sample value)
{ return Luminance(value.L_s); }     // Equation (10).

[numthreads(8, 8, 1)]
void main( uint3 dispatchId : SV_DispatchThreadID )
{
    // [Ouyang 2021] Y.Ouyang, Si.Liu, M.Kettunen, M.Pharr, J.Pataleoni,
    // "ReSTIR GI: Path Resampling for Real-Time Path Tracing", HPG 2021.
    // Algorithm 3. Temporal Resampling.

    // 乱数初期化.
    uint4 seed = SetSeed(dispatchId.xy, SceneParam.FrameIndex);

    // バッファ番号計算.
    uint index = dispatchId.x + dispatchId.y * uint(SceneParam.Size.x);

    Reservoir S = InitialSampleBuffer[index];
    Reservoir R = TemporalReservoirBuffer[index];

    float w = CalcTargetPDF(S.z) / CalcSourcePDF(S.z);  // Equation (5)
    R.Update(S.z, w, Random(seed));
    R.W = R.w_sum / (R.M * CalcTargetPDF(R.z));         // Equation (7)

    TemporalReservoirBuffer[index] = R;
}
