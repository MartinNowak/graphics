module skia.core.blitter_detail.blit_row_sse;

private {
  import std.range : popFront, front, empty, isRandomAccessRange;
  import skia.core.color;
}

static void Color32(Range)(Range srcDst, PMColor pmColor) {
  return Color32(srcDst, srcDst, pmColor);
}

static void Color32(Range)(Range dstR, Range srcR, PMColor pmColor)
  if(isRandomAccessRange!Range) {

  if (!srcR.length)
    return;
  if (pmColor.argb == 0) {
    if (!(dstR is srcR))
      dstR[] = srcR[];
  }

  if (pmColor.a == 255) {
    dstR[] = pmColor;
  } else {
    size_t count = srcR.length;
    uint scale = Color.getInvAlphaFactor(pmColor.a);
    PMColor* src = srcR.ptr;
    PMColor* dst = dstR.ptr;

    assert((cast(size_t)dst & 0x03) == 0);

    // single process until 16-byte aligned
    while (count > 0) {
      if ((cast(size_t)dst & 0x0F) == 0)
        break;
      *dst = pmColor + src.mulAlpha(scale);
      ++src; ++dst;
      --count;
    }

    enum rb_mask = ColorMask!("rb");
    uint color = pmColor.argb;
    if (count >= 4) {
      version (D_InlineAsm_X86) {
          asm {
            //! const 4x0x00FF00FF -> XMM2 : rb_mask
            mov EAX, rb_mask;
            movd XMM0, EAX;
            pshufd XMM2, XMM0, 0x00;

            //! const 4x32bit -> XMM3 : color
            mov EAX, color;
            movd XMM0, EAX;
            pshufd XMM3, XMM0, 0x00;

            //! const 8x16bit -> XMM4 : scale
            mov EAX, scale;
            movd XMM0, EAX;
            punpcklwd XMM0, XMM0;
            pshufd XMM4, XMM0, 0x00;

            mov ECX, count;
            mov ESI, src;
            mov EDI, dst;

          doFour:
            //! Load 4 pixel unaligned from src
            movdqu XMM0, [ESI];

            //! and with rb_mask -> XMM1 : src_rb
            movdqa XMM1, XMM2;
            pand XMM1, XMM0;

            //! shift right src -> XMM0 : src_ag
            psrlw XMM0, 8;

            //! multiply src_rb, src_ag with scale
            pmullw XMM1, XMM4;
            pmullw XMM0, XMM4;

            //! treat multiplication result
            psrlw XMM1, 8;
            movdqa XMM5, XMM2;
            pandn XMM5, XMM0;

            //! combine rb and ag
            por XMM1, XMM5;

            //! Add fixed color
            paddb XMM1, XMM3;

            //! Write back result aligned
            movdqa [EDI], XMM1;

            add ESI, 16;
            add EDI, 16;
            sub ECX, 4;
            cmp ECX, 4;
            ja doFour;

            mov src, ESI;
            mov dst, EDI;
            mov count, ECX;

          end:
            ;
          }
      } else version (D_InlineAsm_X86_64) {
          asm {
            //! const 4x0x00FF00FF -> XMM2 : rb_mask
            mov EAX, rb_mask;
            movd XMM0, EAX;
            pshufd XMM2, XMM0, 0x00;

            //! const 4x32bit -> XMM3 : color
            mov EAX, color;
            movd XMM0, EAX;
            pshufd XMM3, XMM0, 0x00;

            //! const 8x16bit -> XMM4 : scale
            mov EAX, scale;
            movd XMM0, EAX;
            punpcklwd XMM0, XMM0;
            pshufd XMM4, XMM0, 0x00;

            mov RCX, count;
            mov RSI, src;
            mov RDI, dst;

          doFour:
            //! Load 4 pixel unaligned from src
            movdqu XMM0, [ESI];

            //! and with rb_mask -> XMM1 : src_rb
            movdqa XMM1, XMM2;
            pand XMM1, XMM0;

            //! shift right src -> XMM0 : src_ag
            psrlw XMM0, 8;

            //! multiply src_rb, src_ag with scale
            pmullw XMM1, XMM4;
            pmullw XMM0, XMM4;

            //! treat multiplication result
            psrlw XMM1, 8;
            movdqa XMM5, XMM2;
            pandn XMM5, XMM0;

            //! combine rb and ag
            por XMM1, XMM5;

            //! Add fixed color
            paddb XMM1, XMM3;

            //! Write back result aligned
            movdqa [EDI], XMM1;

            add RSI, 16;
            add RDI, 16;
            sub RCX, 4;
            cmp RCX, 4;
            ja doFour;

            mov src, RSI;
            mov dst, RDI;
            mov count, RCX;

          end:
            ;
          }
        }
    }

    while (count > 0) {
        *dst = pmColor + src.mulAlpha(scale);
        ++src; ++dst;
        --count;
    }
  }
}
