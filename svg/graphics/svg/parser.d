module graphics.svg.parser;

import std.experimental.xml.interfaces : isCursor;

// Flatten the attributes of the cursor's current element into a map.
string[string] attrs(CursorType)(ref CursorType cursor) if (isCursor!CursorType)
{
    string[string] res;
    foreach (a; cursor.attributes)
        res[a.name] = a.value;
    return res;
}
