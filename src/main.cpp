//-----------------------------------------------------------------------------
// File : main.cpp
// Desc : Main Entry Point.
// Copyright(c) Project Asura. All right reserved.
//-----------------------------------------------------------------------------

//-----------------------------------------------------------------------------
// Includes
//-----------------------------------------------------------------------------
#include <renderer.h>


//-----------------------------------------------------------------------------
//      メインエントリーポイントです.
//-----------------------------------------------------------------------------
int main(int argc, char** argv)
{
    r3d::SceneDesc desc = {};
    desc.TimeSec    = 10.0 * 59.0;
    desc.Width      = 2560;
    desc.Height     = 1440;

    r3d::Renderer app(desc);
    app.Run();

    return 0;
}