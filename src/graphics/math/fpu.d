module graphics.math.fpu;

enum FpuException {
  InvalidOp = (1<<0),
  Denormalized = (1<<1),
  ZeroDiv = (1<<2),
  Overflow = (1<<3),
  Underflow = (1<<4),
  Precision = (1<<5),
  AllExceptionsMask = 0x3f,
}

enum SSEException {
  InvalidOp = (1<<7),
  Denormalized = (1<<8),
  ZeroDiv = (1<<9),
  Overflow = (1<<10),
  Underflow = (1<<11),
  Precision = (1<<12),
  AllExceptionsMask = 0x1f80,
}

enum MXCSR {
  DenormalsAreZero = (1<<6),
  FlushToZero = (1 << 15),
}

void enableFpuException(ushort e) {
  assert((e & ~FpuException.AllExceptionsMask) == 0);
  auto control = getFpuCW();
  control &= ~e;
  setFpuCW(control);
}

void disableFpuException(ushort e) {
  assert((e & ~FpuException.AllExceptionsMask) == 0);
  auto control = getFpuCW();
  control |= e;
  setFpuCW(control);
}

void enableSSEException(uint e) {
  assert((e & ~SSEException.AllExceptionsMask) == 0);
  auto control = getMXCSR();
  control &= ~e;
  setMXCSR(control);
}

void disableSSEException(uint e) {
  assert((e & ~SSEException.AllExceptionsMask) == 0);
  auto control = getMXCSR();
  control |= e;
  setMXCSR(control);
}

void enableFlushToZeroDAZ() {
  auto control = getMXCSR();
  control |= SSEException.Denormalized | MXCSR.FlushToZero | MXCSR.DenormalsAreZero;
  setMXCSR(control);
}

// Need to disable InvalidOp as floats are initalized to NaN by default.
void enableDefaultFpuExceptions() {
  enableFpuException(FpuException.AllExceptionsMask ^ (FpuException.Precision | FpuException.InvalidOp));
  enableSSEException(SSEException.AllExceptionsMask ^ (SSEException.Precision | SSEException.InvalidOp));
  enableFlushToZeroDAZ();
}

private:

ushort getFpuCW() {
  ushort control;
  auto pcw = &control;
  version (D_InlineAsm_X86) {
    asm {
      mov EBX, pcw;
      fstcw [EBX];
    }
  } else version (D_InlineAsm_X86_64) {
    asm {
      mov RBX, pcw;
      fstcw [RBX];
    }
  }
  return control;
}

void setFpuCW(ushort control) {
  auto pcw = &control;
  version (D_InlineAsm_X86) {
    asm {
      mov EBX, pcw;
      fldcw [EBX];
    }
  } else version (D_InlineAsm_X86_64) {
    asm {
      mov RBX, pcw;
      fldcw [RBX];
    }
  }
}

uint getMXCSR() {
  uint control;
  auto pcw = &control;
  version (D_InlineAsm_X86) {
    asm {
      mov EBX, pcw;
      stmxcsr [EBX];
    }
  } else version (D_InlineAsm_X86_64) {
    asm {
      mov RBX, pcw;
      stmxcsr [RBX];
    }
  }
  return control;
}

void setMXCSR(uint control) {
  auto pcw = &control;
  version (D_InlineAsm_X86) {
    asm {
      mov EBX, pcw;
      ldmxcsr [EBX];
    }
  } else version (D_InlineAsm_X86_64) {
    asm {
      mov RBX, pcw;
      ldmxcsr [RBX];
    }
  }
}