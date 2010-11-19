module skia.core.region;

import skia.core.rect : IRect;

struct Region
{
  IRect _rect;
  alias _rect this;
public:
  this(in IRect rect) {
    this._rect = rect;
  }

  enum Op {
    kDifference, /// subtract the op region from the first region
    kIntersect,  /// intersect the two regions
    kUnion,      /// union (inclusive-or) the two regions
    kXOR,        /// exclusive-or the two regions
    /** subtract the first region from the op region */
    kReverseDifference,
    kReplace,    /// replace the dst region with the op region
  }
}