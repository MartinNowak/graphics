module graphics.core.matrix;

import std.ascii, std.bitmanip, std.complex, std.conv, std.exception, std.math;
import guip.point, guip.rect;
import graphics.math.poly;

struct Matrix
{
    static immutable float[3][3] identity = [
        [1.0f, 0.0f, 0.0f],
        [0.0f, 1.0f, 0.0f],
        [0.0f, 0.0f, 1.0f],
    ];

    float[3][3] _data = [
        [1.0f, 0.0f, 0.0f],
        [0.0f, 1.0f, 0.0f],
        [0.0f, 0.0f, 1.0f],
    ];

    alias _data this;

    @property string toString()
    {
        alias std.ascii.newline nl;
        return text(_data[0], nl, _data[1], nl, _data[2]);
    }

    /****************************************
     * Matrix manipulation functions.
     */
    void reset()
    {
        _data = identity;
    }


    @property Matrix inverted() const
    {
        auto scale = 1.0 / determinant();
        enforce(isFinite(scale), "Matrix determinant underflow");

        Matrix res=void;

        res[0][0] = scale * (_data[1][1] * _data[2][2]  - _data[1][2] * _data[2][1]);
        res[0][1] = scale * (_data[0][2] * _data[2][1]  - _data[0][1] * _data[2][2]);

        res[1][0] = scale * (_data[1][2] * _data[2][0]  - _data[1][0] * _data[2][2]);
        res[1][1] = scale * (_data[0][0] * _data[2][2]  - _data[0][2] * _data[2][0]);

        res[2][0] = scale * (_data[1][0] * _data[2][1]  - _data[1][1] * _data[2][0]);
        res[2][1] = scale * (_data[0][1] * _data[2][0]  - _data[0][0] * _data[2][1]);

        res[0][2] = scale * (_data[0][1] * _data[1][2]  - _data[0][2] * _data[1][1]);
        res[1][2] = scale * (_data[0][2] * _data[1][0]  - _data[0][0] * _data[1][2]);
        res[2][2] = scale * (_data[0][0] * _data[1][1]  - _data[0][1] * _data[1][0]);

        return res;
    }

    private real determinant() const
    {
        return
            _data[0][0] * (_data[1][1] * _data[2][2] - _data[1][2] * _data[2][1]) +
            _data[0][1] * (_data[1][2] * _data[2][0] - _data[1][0] * _data[2][2]) +
            _data[0][2] * (_data[1][0] * _data[2][1] - _data[1][1] * _data[2][0]);
    }

    private template pre(string setf)
    {
        Matrix pre(Args...)(Args args) const
        {
            Matrix m=void;
            mixin(`m.`~setf~`(args);`);
            return this * m;
        }
    }

    private template post(string setf)
    {
        Matrix post(Args...)(Args args) const
        {
            Matrix m=void;
            mixin(`m.`~setf~`(args);`);
            return m * this;
        }
    }

    void setTranslate(float dx, float dy)
    {
        reset();
        _data[0][2] = dx;
        _data[1][2] = dy;
    }
    alias  pre!q{setTranslate}  preTranslate;
    alias post!q{setTranslate} postTranslate;

    void setRotate(float deg)
    {
        reset();
        immutable rad = deg * 2 * PI / 360.0f;
        setSinCos(sin(rad), cos(rad));
    }

    void setRotate(float deg, float px, float py)
    {
        reset();
        immutable rad = deg * 2 * PI / 360.0f;
        immutable sincos = expi(rad);
        setSinCos(sincos.im, sincos.re, px, py);
    }
    alias  pre!q{setRotate}  preRotate;
    alias post!q{setRotate} postRotate;

    void setScale(float xs, float ys)
    {
        reset();
        _data[0][0] = xs;
        _data[1][1] = ys;
    }
    alias  pre!q{setScale}  preScale;
    alias post!q{setScale} postScale;

    void setSkewX(float sx)
    {
        reset();
        _data[2][0] = sx;
    }
    alias  pre!q{setSkewX}  preSkewX;
    alias post!q{setSkewX} postSkewX;

    void setSkewY(float sy)
    {
        reset();
        _data[2][1] = sy;
    }
    alias  pre!q{setSkewY}  preSkewY;
    alias post!q{setSkewY} postSkewY;

    @property translativeOnly() const
    {
        return !perspective &&
            _data[0][0] == identity[0][0] &&
            _data[0][1] == identity[0][1] &&
            _data[1][0] == identity[1][0] &&
            _data[1][1] == identity[1][1];
    }

    @property bool perspective() const
    {
        return
            _data[2][0] != identity[2][0] ||
            _data[2][1] != identity[2][1] ||
            _data[2][2] != identity[2][2];
    }

    /****************************************
     * Matrix calculation functions.
     */
    FRect mapRect(in FRect src) const
    {
        FPoint[4] pts=void;
        pts[0].x = src.left;   pts[0].y = src.top;
        pts[1].x = src.right;  pts[1].y = src.top;
        pts[2].x = src.right;  pts[2].y = src.bottom;
        pts[3].x = src.left;   pts[3].y = src.bottom;

        mapPoints(pts[]);

        return FRect.calcBounds(pts);
    }

    void mapPoints(FPoint[] pts) const
    {
        foreach(ref pt; pts)
            pt = this * pt;
    }

    Matrix opBinary(string op)(Matrix rhs) const if (op == "*")
    {
        Matrix res=void;
        // TODO: check if worth to unroll loop
        foreach(row; 0 .. 3)
        {
            foreach(col; 0 .. 3)
            {
                res[row][col] =
                    _data[row][0] * rhs[0][col] +
                    _data[row][1] * rhs[1][col] +
                    _data[row][2] * rhs[2][col];
            }
        }
        return res;
    }

    FPoint opBinary(string op)(FPoint pt) const if (op == "*")
    {
        immutable x = pt.x * _data[0][0] + pt.y * _data[0][1] + _data[0][2];
        immutable y = pt.x * _data[1][0] + pt.y * _data[1][1] + _data[1][2];
        immutable w = pt.x * _data[2][0] + pt.y * _data[2][1] + _data[2][2];
        immutable iw = 1.0f / w;
        return FPoint(x * iw, y * iw);
    }

private:

    public void setSinCos(float sinV, float cosV)
    {
        _data[0][0] = cosV;
        _data[0][1] = -sinV;
        _data[1][0] = sinV;
        _data[1][1] = cosV;
    }

    void setSinCos(float sinV, float cosV, float px, float py)
    {
        setSinCos(sinV, cosV);
        _data[0][2] =  sinV * py - cosV * px + px;
        _data[1][2] = -sinV * px - cosV * py + py;
    }
}

unittest
{
    import std.math : abs;

    bool nearF(float a, float b) { return abs(a - b) < 1e-4f; }
    bool nearM(in Matrix a, in Matrix b)
    {
        foreach (r; 0 .. 3)
            foreach (c; 0 .. 3)
                if (!nearF(a[r][c], b[r][c]))
                    return false;
        return true;
    }
    bool nearP(FPoint a, FPoint b) { return abs(a.x - b.x) < 1e-4f && abs(a.y - b.y) < 1e-4f; }

    Matrix m;
    assert(nearF(m[0][0], 1.0f) && nearF(m[1][1], 1.0f) && nearF(m[2][2], 1.0f));
    assert(m.toString.length > 0);

    // reset
    m.setTranslate(5, 6);
    m.reset();
    assert(nearM(m, Matrix(Matrix.identity)));

    // translate
    m.setTranslate(3, 4);
    assert(!m.perspective);
    assert(nearP(m * FPoint(1, 2), FPoint(4, 6)));
    assert(m.translativeOnly);

    // rotate 90 degrees about origin
    m.setRotate(90);
    assert(nearP(m * FPoint(1, 0), FPoint(0, 1)));
    assert(!m.translativeOnly);
    assert(!m.perspective);

    // rotate about a pivot leaves the pivot in place
    m.setRotate(45, 10, 20);
    assert(nearP(m * FPoint(10, 20), FPoint(10, 20)));

    // scale
    m.setScale(2, 3);
    assert(nearP(m * FPoint(1, 1), FPoint(2, 3)));
    assert(!m.translativeOnly && !m.perspective);

    // skew is perspective
    m.setSkewX(0.5f);
    assert(m.perspective);
    m.setSkewY(0.25f);
    assert(m.perspective);

    // pre/post variants and multiplication
    m.reset();
    auto t = m.preTranslate(10, 0);
    assert(nearP(t * FPoint(0, 0), FPoint(10, 0)));
    auto s = t.preScale(2, 2);
    assert(nearP(s * FPoint(0, 0), FPoint(10, 0)));
    auto p = t.postScale(2, 2);
    assert(nearP(p * FPoint(0, 0), FPoint(20, 0)));

    // identity * identity == identity
    Matrix i;
    assert(nearM(i * i, i));

    // mapPoints / mapRect
    m.setTranslate(1, 1);
    FPoint[3] pts = [FPoint(0, 0), FPoint(1, 0), FPoint(0, 1)];
    m.mapPoints(pts[]);
    assert(nearP(pts[0], FPoint(1, 1)) && nearP(pts[1], FPoint(2, 1)));
    auto r = m.mapRect(FRect(FPoint(0, 0), FPoint(2, 3)));
    assert(nearF(r.left, 1) && nearF(r.top, 1) && nearF(r.right, 3) && nearF(r.bottom, 4));

    // inverse: M * M.inverted == identity for a full affine
    m.setRotate(30, 7, 9);
    m = m.preTranslate(11, -3);
    m = m.preScale(2, 0.5f);
    auto inv = m.inverted;
    assert(nearM(m * inv, i));
    assert(nearM(inv * m, i));

    // inverse of a pure translation
    m.setTranslate(3, 4);
    assert(nearP(m.inverted * FPoint(3, 4), FPoint(0, 0)));

    // singular matrix throws
    import std.exception : assertThrown;
    Matrix singular;
    singular.setScale(0, 1);
    assertThrown(singular.inverted);
}
