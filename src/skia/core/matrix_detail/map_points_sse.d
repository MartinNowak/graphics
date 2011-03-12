module skia.core.matrix_detail.map_points_sse;

private {
  import std.conv : to;
  import skia.core.matrix;
  import guip.point;
}

alias void function(in Matrix, FPoint[]) MapPtsFunc;
MapPtsFunc mapPtsFunc(ubyte typeMaskTrans) {
  switch(typeMaskTrans) {
  case 0:
    return &IdentityPts;
  case 1: ..case 7:
    return &SSERotTransPts;
  default:
    return &PerspPts;
  }
}

static void IdentityPts(in Matrix, FPoint[]) {
  return;
}

static void SSERotTransPts(in Matrix m, FPoint[] pts) {
  assert((m.typeMaskTrans & Matrix.Type.Perspective) == 0);
  assert(pts.length > 0);
  auto row1 = &m[0][0];
  auto row2 = &m[1][0];
  auto ppts = pts.ptr;
  auto len = pts.length;
  float[2] Trans = [m[0][2], m[1][2]];
  auto pTrans = &Trans[0];

  // TODO: Try to switch to movaps when pts are 16-byte aligned, or
  // process unaligned until the are aligned.
  version (D_InlineAsm_X86) {
    asm {
      mov EAX, row1;
      mov EBX, row2;
      mov ECX, len;
      mov ESI, ppts;

      // XMMO m00 m01 m10 m11
      // XMM1 m10 m11 m00 m01
      movlps XMM0, [EAX];
      movhps XMM0, [EBX];
      movaps XMM1, XMM0;
      shufps XMM0, XMM0, 0b11_00_11_00;
      shufps XMM1, XMM1, 0b10_01_10_01;
      mov EAX, pTrans;
      movlps XMM2, [EAX];
      movhps XMM2, [EAX];

    dotwoa:
      cmp ECX, 2;
      jb epilog;
      movups XMM3, [ESI];
      movaps XMM4, XMM3;
      shufps XMM4, XMM3, 0b10_11_00_01;
      mulps XMM3, XMM0;
      mulps XMM4, XMM1;
      addps XMM3, XMM4;
      // Add translation
      addps XMM3,  XMM2;
      movups [ESI], XMM3;
      add ESI, 16;
      sub ECX, 2;
    loopa:
      jmp dotwoa;

    epilog:
      cmp ECX, 1;
      jb end;
      movlps XMM3, [ESI];
      movaps XMM4, XMM3;
      shufps XMM4, XMM3, 0b10_11_00_01;
      mulps XMM3, XMM0;
      mulps XMM4, XMM1;
      addps XMM3, XMM4;
      // Add translation
      addps XMM3, XMM2;
      movlps [ESI], XMM3;
      add ESI, 8;
      sub ECX, 1;

    end:
      mov len, ECX;
      mov ppts, ESI;
      ;
    }
  } else version (D_InlineAsm_X86_64) {
    asm {
      mov RAX, row1;
      mov RBX, row2;
      mov RCX, len;
      mov RSI, ppts;

      // XMMO m00 m01 m10 m11
      // XMM1 m10 m11 m00 m01
      movlps XMM0, [RAX];
      movhps XMM0, [RBX];
      movaps XMM1, XMM0;
      shufps XMM0, XMM0, 0b11_00_11_00;
      shufps XMM1, XMM1, 0b10_01_10_01;
      mov RAX, pTrans;
      movlps XMM2, [RAX];
      movhps XMM2, [RAX];

    dotwoa:
      cmp ECX, 2;
      jb epilog;
      movups XMM3, [RSI];
      movaps XMM4, XMM3;
      shufps XMM4, XMM3, 0b10_11_00_01;
      mulps XMM3, XMM0;
      mulps XMM4, XMM1;
      addps XMM3, XMM4;
      // Add translation
      addps XMM3,  XMM2;
      movups [RSI], XMM3;
      add RSI, 16;
      sub RCX, 2;
    loopa:
      jmp dotwoa;

    epilog:
      cmp RCX, 1;
      jb end;
      movlps XMM3, [RSI];
      movaps XMM4, XMM3;
      shufps XMM4, XMM3, 0b10_11_00_01;
      mulps XMM3, XMM0;
      mulps XMM4, XMM1;
      addps XMM3, XMM4;
      // Add translation
      addps XMM3, XMM2;
      movlps [RSI], XMM3;
      add RSI, 8;
      sub RCX, 1;

    end:
      mov len, RCX;
      mov ppts, RSI;
      ;
    }
  }
  assert(len == 0);
  assert(ppts == pts.ptr + pts.length);
}

// TODO: assembly code for perspective mapping.
static void PerspPts(in Matrix m, FPoint[] pts) {
  assert(m.typeMaskTrans & Matrix.Type.Perspective);

  auto sPt = FPoint(m[0][0], m[1][1]);
  auto tPt = FPoint(m[0][2], m[1][2]);

  auto p0 = m[2][0];
  auto p1 = m[2][1];
  auto p2 = m[2][2];

  foreach(ref pt; pts) {
    auto z = pt.x * p0 + pt.y * p1 + p2;
    auto skewPt = point(pt.y * m[0][1], pt.x * m[1][0]);
    pt = pt * sPt + skewPt + tPt;
    if (z)
      pt /= z;
  }
}

unittest {
  Matrix m;
  m.reset();
  m[0][0] = 2.0f;
  m[0][1] = -1.0f;
  m[1][0] = 0.5f;
  m[1][2] = 1.0f;
  auto pts = [FPoint(5.0f, 5.0f), FPoint(1.0f, 1.0f), FPoint(2.0f, 3.0f), FPoint(-1.0f, 4.0f)];
  SSERotTransPts(m, pts);
  assert(pts == [FPoint(5.0f, 8.5f), FPoint(1.0f, 2.5f), FPoint(1.0f, 5.0f), FPoint(-6.0f, 4.5f)],
         to!string(pts));
}
