//-----------------------------------------------------------------------------
// File : RtCamp.hlsl
// Desc : レイトレ合宿提出用シェーダ.
// Copyright(c) Project Asura. All right resreved.
//-----------------------------------------------------------------------------

//-----------------------------------------------------------------------------
// Includes
//-----------------------------------------------------------------------------
#include <Common.hlsli>

#define FURNANCE_TEST       (0)

//-----------------------------------------------------------------------------
// Resources
//-----------------------------------------------------------------------------
RWTexture2D<float4>             Canvas      : register(u0);
Texture2D<float4>               BackGround  : register(t4);


//-----------------------------------------------------------------------------
//      IBLをサンプルします.
//-----------------------------------------------------------------------------
float3 SampleIBL(float3 dir)
{
    float2 uv = ToSphereMapCoord(dir);
    return BackGround.SampleLevel(LinearWrap, uv, 0.0f).rgb * SceneParam.SkyIntensity;
}

//-----------------------------------------------------------------------------
//      レイ生成シェーダです.
//-----------------------------------------------------------------------------
[shader("raygeneration")]
void OnGenerateRay()
{
    // 乱数初期化.
    uint4 seed = SetSeed(DispatchRaysIndex().xy, SceneParam.FrameIndex);

    float2 pixel = float2(DispatchRaysIndex().xy);
    const float2 resolution = float2(DispatchRaysDimensions().xy);

    // アンリエイリアシング.
    float2 offset = float2(Random(seed), Random(seed));
    pixel += lerp(-0.5f.xx, 0.5f.xx, offset);

    float2 uv = (pixel + 0.5f) / resolution;
    uv.y = 1.0f - uv.y;
    pixel = uv * 2.0f - 1.0f;

    // ペイロード初期化.
    Payload payload = (Payload)0;

    // レイを設定.
    RayDesc ray = GeneratePinholeCameraRay(pixel);

    float3 W = float3(1.0f, 1.0f, 1.0f);  // 重み.
    float3 L = float3(0.0f, 0.0f, 0.0f);  // 放射輝度.

    for(int bounce=0; /*bounce<SceneParam.MaxBounce*/; ++bounce)
    {
        // 交差判定.
        TraceRay(
            SceneAS,
            RAY_FLAG_NONE,
            0xFF,
            STANDARD_RAY_INDEX,
            0,
            STANDARD_RAY_INDEX,
            ray,
            payload);

        if (!payload.HasHit())
        {
        #if FURNANCE_TEST
            L += W * float3(0.5f, 0.5f, 0.5f); // Furnance Test.
        #else
            L += W * SampleIBL(ray.Direction);
        #endif
            break;
        }

        // 頂点データ取得.
        Vertex vertex = GetVertex(payload.InstanceId, payload.PrimitiveId, payload.Barycentrics);

        // マテリアル取得.
        Material material = GetMaterial(payload.InstanceId, vertex.TexCoord, 0.0f);

        float3 B = normalize(cross(vertex.Tangent, vertex.Normal));
        float3 N = FromTangentSpaceToWorld(material.Normal, vertex.Tangent, B, vertex.Normal);

        float3 geometryNormal = vertex.GeometryNormal;
        float3 V = -ray.Direction;
        if (dot(geometryNormal, V) < 0.0f)
        { geometryNormal = -geometryNormal; }

        // 面の下に潜っている場合は反転.
        if (dot(geometryNormal, N) < 0.0f)
        { N = -N; }

        // 自己発光による放射輝度.
        L += W * material.Emissive;

#if 0
        // Next Event Estimation.
        {
            // BSDFがPerfect Specular以外の成分を持っている場合.
            if (!IsPerfectSpecular(material))
            {
                // 光源をサンプリング.
                float lightPdf;
                float2 st = SampleMipMap(BackGround, float2(Random(seed), Random(seed)), lightPdf);

                // 方向ベクトルに変換.
                float3 dir = FromSphereMapCoord(st);

                if (!CastShadowRay(vertex.Position, geometryNormal, dir, FLT_MAX))
                {
                    // シャドウレイを飛ばして，光源上のサンプリングとレイ原点の間に遮断が無い場合.
                    float cosShadow = abs(dot(N, dir));
                    float cosLight  = 1.0f;
                    float3 fs = material.BaseColor.rgb / F_PI;

                    float G = (cosShadow * cosLight);

                    float brdfPdf = abs(dir.z / F_PI) * cosLight;
                    float misWeight = lightPdf / (brdfPdf + lightPdf);

                    float3 lightIntensity = BackGround.SampleLevel(LinearWrap, st, 0.0f).rgb;

                    L += (W * lightIntensity * fs * G /*/ lightPdf*/)/* * misWeight*/;
                    //L += W * lightIntensity * fs * G * brdfPdf;

                }

                //// 光源上の1点をランダムにサンプリング.
                //float3 lightPos;    // 光源上の位置.
                //float  lightPdf;    // 光源の確率密度関数.
                ////SampleLight();

                ////float3 L      = lightPos - vertex.Position;
                ////float  distSq = dot(dir, dir);
                ////float  dist   = sqrt(distSq);
                ////L /= dist;

                //// 光源上のサンプリング点に向かってシャドウレイを飛ばす.
                //if (CastShadowRay(lightPos, geometryNormal, dir, len))
                //{
                //    // シャドウレイを飛ばして，光源上のサンプリングとレイ原点の間に遮蔽が無い場合

                //    float cosShadow = abs(dot(N, L));
                //    float cosLight  = abs(dot(lightN, -L));
                //    float fs = material.BaseColor.rgb / F_PI;
                //    float G  = (cosShadow * cosLight) / distSq;

                //    float brdfPdf = abs(dir.z / F_PI) * cosLight / distSq;
                //    float misWeight = lightPdf / (brdfPdf + lightPdf);
                //  
                //    // L += W * Light * BRDF * G / lightPDF.
                //    L += (W * light.Intensity * fs * G / lightPdf) * misWeight;
                //}
            }
        }
#endif

        // 最後のバウンスであれば早期終了(BRDFをサンプルしてもロジック的に反映されないため).
        if (bounce == SceneParam.MaxBounce - 1)
        { break; }

        // シェーディング処理.
        float3 u = float3(Random(seed), Random(seed), Random(seed));
        float3 dir;
        float  pdf;
        float3 brdf = EvaluateMaterial(V, N, u, material, dir, pdf);

        // ロシアンルーレット.
        if (bounce > SceneParam.MinBounce)
        {
            float p = min(0.95f, Luminance(brdf));
            if (p > Random(seed))
            { break; }
        }

        W *= brdf / pdf;

        // 重みがゼロに成ったら以降の更新は無駄なので打ち切りにする.
        if (all(W <= (0.0f).xxx))
        { break; }

        // レイを更新.
        ray.Origin    = OffsetRay(vertex.Position, geometryNormal);
        ray.Direction = dir;
    }

    uint2 launchId = DispatchRaysIndex().xy;

    float3 prevL = Canvas[launchId].rgb;
    float3 color = (SceneParam.EnableAccumulation) ? (prevL + L) : L;

    Canvas[launchId] = float4(color, 1.0f);
}

//-----------------------------------------------------------------------------
//      ヒット時のシェーダ.
//-----------------------------------------------------------------------------
[shader("closesthit")]
void OnClosestHit(inout Payload payload, in HitArgs args)
{
    payload.InstanceId   = InstanceID();
    payload.PrimitiveId  = PrimitiveIndex();
    payload.Barycentrics = args.barycentrics;
}

//-----------------------------------------------------------------------------
//      ミスシェーダです.
//-----------------------------------------------------------------------------
[shader("miss")]
void OnMiss(inout Payload payload)
{ payload.InstanceId = INVALID_ID; }

//-----------------------------------------------------------------------------
//      シャドウレイヒット時のシェーダ.
//-----------------------------------------------------------------------------
[shader("closesthit")]
void OnShadowClosestHit(inout ShadowPayload payload, in HitArgs args)
{
    payload.Visible      = true;
    payload.Barycentrics = args.barycentrics;
}

//-----------------------------------------------------------------------------
//      シャドウレイのミスシェーダです.
//-----------------------------------------------------------------------------
[shader("miss")]
void OnShadowMiss(inout ShadowPayload payload)
{ payload.Visible = false; }

