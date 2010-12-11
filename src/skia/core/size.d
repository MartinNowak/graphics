module skia.core.size;

alias Size!(int) ISize;
alias Size!(float) FSize;

////////////////////////////////////////////////////////////////////////////////
//
////////////////////////////////////////////////////////////////////////////////

struct Size(T)
{
  T width, height;
  this (T width, T height) {
    this.width = width;
    this.height = height;
  }

  @property bool empty() const {
    return this.width > 0 && this.height > 0;
  }
}


