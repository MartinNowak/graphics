module skia.core.xfermode;

private {
  import skia.core.color;
}

/**
 * Xfermode is the base class for objects that are called to implement
 * custom "transfer-modes" in the drawing pipeline. The static
 * function Create(Modes) can be called to return an instance of any
 * of the predefined subclasses as specified in the Modes enum. When
 * an SkXfermode is assigned to an SkPaint, then objects drawn with
 * that paint have the xfermode applied.
 */
interface XferMode {

  /** List of predefined xfermodes.  The algebra for the modes uses
   *  the following symbols: Sa, Sc - source alpha and color Da, Dc
   *  - destination alpha and color (before compositing) [a, c] -
   *  Resulting (alpha, color) values For these equations, the
   *  colors are in premultiplied state.  If no xfermode is
   *  specified, kSrcOver is assumed.
   */
  enum Mode {
    Clear,    //!< [0, 0]
    Src,      //!< [Sa, Sc]
    Dst,      //!< [Da, Dc]
    SrcOver,  //!< [Sa + Da - Sa*Da, Rc = Sc + (1 - Sa)*Dc]
    DstOver,  //!< [Sa + Da - Sa*Da, Rc = Dc + (1 - Da)*Sc]
    SrcIn,    //!< [Sa * Da, Sc * Da]
    DstIn,    //!< [Sa * Da, Sa * Dc]
    SrcOut,   //!< [Sa * (1 - Da), Sc * (1 - Da)]
    DstOut,   //!< [Da * (1 - Sa), Dc * (1 - Sa)]
    SrcATop,  //!< [Da, Sc * Da + (1 - Sa) * Dc]
    DstATop,  //!< [Sa, Sa * Dc + Sc * (1 - Da)]
    Xor,      //!< [Sa + Da - 2 * Sa * Da, Sc * (1 - Da) + (1 - Sa) * Dc]

    // these modes are defined in the SVG Compositing standard
    // http://www.w3.org/TR/2009/WD-SVGCompositing-20090430/
    Plus,
    Multiply,
    Screen,
    Overlay,
    Darken,
    Lighten,
    ColorDodge,
    ColorBurn,
    HardLight,
    SoftLight,
    Difference,
    Exclusion,

    LastMode = Exclusion,
  };

  enum Coeff {
    Zero,    /** 0 */
    One,     /** 1 */
    SC,      /** src color */
    ISC,     /** inverse src color (i.e. 1 - sc) */
    DC,      /** dst color */
    IDC,     /** inverse dst color (i.e. 1 - dc) */
    SA,      /** src alpha */
    ISA,     /** inverse src alpha (i.e. 1 - sa) */
    DA,      /** dst alpha */
    IDA,     /** inverse dst alpha (i.e. 1 - da) */

    CoeffCount
  };

  final static XferMode Create(XferMode.Mode mode) {
    return null;
  }

  void xfer32(PMColor dst[], in PMColor src[], int count, in Alpha aa[]);
  void xfer16(ushort dst[], in PMColor src[], int count, in Alpha aa[]);
  void xfer4444(ushort dst[], in PMColor src[], int count, in Alpha aa[]);
  void xferA8(Alpha dst[], in PMColor src[], int count, in Alpha aa[]);

  /**
   * If the xfermode can be expressed as an equation using the
   * coefficients in Coeff, then asCoeff() returns true, and sets (if
   * not null) src and dst accordingly.

   *     result = src_coeff * src_color + dst_coeff * dst_color;

   * As examples, here are some of the porterduff coefficients
   *     MODE        SRC_COEFF       DST_COEFF
   *     clear       zero            zero
   *     src         one             zero
   *     dst         zero            one
   *     srcover     one             isa
   *     dstover     ida             one
   */
  bool asCoeff(out Coeff src, out Coeff dst);
}
