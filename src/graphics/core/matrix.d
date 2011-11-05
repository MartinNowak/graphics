module graphics.core.matrix;

import std.bitmanip, std.conv, std.exception, std.math;
import guip.point, guip.rect;
import graphics.math.poly;

immutable float[3][3] identity =
[
    [1.0f, 0.0f, 0.0f],
    [0.0f, 1.0f, 0.0f],
    [0.0f, 0.0f, 1.0f],
];

struct Matrix
{
    float[3][3] _data=identity;
    alias _data this;

    @property string toString()
    {
        alias std.string.newline nl;
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
        Matrix pre(Args...)(Args args) const
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

    Matrix opBinary(string op)(ref const Matrix rhs) const if (op == "*")
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
