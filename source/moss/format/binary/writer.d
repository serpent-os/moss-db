/*
 * This file is part of moss.
 *
 * Copyright © 2020 Serpent OS Developers
 *
 * This software is provided 'as-is', without any express or implied
 * warranty. In no event will the authors be held liable for any damages
 * arising from the use of this software.
 *
 * Permission is granted to anyone to use this software for any purpose,
 * including commercial applications, and to alter it and redistribute it
 * freely, subject to the following restrictions:
 *
 * 1. The origin of this software must not be misrepresented; you must not
 *    claim that you wrote the original software. If you use this software
 *    in a product, an acknowledgment in the product documentation would be
 *    appreciated but is not required.
 * 2. Altered source versions must be plainly marked as such, and must not be
 *    misrepresented as being the original software.
 * 3. This notice may not be removed or altered from any source distribution.
 */

module moss.format.binary.writer;

import std.stdio : File;

import moss.format.binary : MossFormatVersionNumber;
import moss.format.binary.endianness;
import moss.format.binary.header;
import moss.format.binary.record;

/**
 * This class is responsible for writing binary moss packages to disk,
 * setting relevant meta-information and merging a payload.
 */
class Writer
{

private:

    string _filename;
    File _file;
    Header _header;

public:
    @disable this();

    /**
     * Construct a new Writer for the given filename
     */
    this(string filename, uint32_t versionNumber = MossFormatVersionNumber) @trusted
    {
        _filename = filename;

        _file = File(filename, "wb");
        _header = Header(versionNumber);
        _header.numRecords = 0;
        _header.toNetworkOrder();

        /* Insert the header now, we'll rewind and fix number of records */
        _file.rawWrite((&_header)[0 .. Header.sizeof]);
    }

    ~this() @safe
    {
        close();
    }

    /**
     * Return the filename for the Writer
     */
    pure final @property const(string) filename() @safe @nogc nothrow
    {
        return _filename;
    }

    /**
     * Flush and close the underying file.
     */
    final void close() @safe
    {
        if (_file.isOpen())
        {
            _file.flush();
            _file.close();
            _file = File();
        }
    }

    /**
     * Attempt to add a record to the stream. The type of T must be the
     * type expected in the key type
     */
    final void addRecord(R : RecordTag, T)(R key, T datum)
    {
        import std.traits;
        import std.conv : to;
        import std.stdio;
        import std.string : toStringz;

        Record record;
        void delegate() encoder;

        void encodeString()
        {
            static if (is(T == string))
            {
                auto z = toStringz(datum);
                assert(datum.length < uint32_t.max, "addRecord(): String Length too long");
                record.type = RecordType.String;
                record.length = cast(uint32_t) datum.length + 1;
                _file.rawWrite(z[0 .. record.length]);
            }
        }

        void encodeNumeric()
        {
            static if (!is(T == string))
            {
                import std.bitmanip;

                record.length = cast(uint32_t) T.sizeof;

                /* Ensure we encode big-endian values only */
                version (BigEndian)
                {
                    _file.rawWrite((&datum)[0 .. T.sizeof]);
                }
                else
                {
                    static if (T.sizeof > 1)
                    {
                        ubyte[T.sizeof] b = nativeToBigEndian(datum);
                        _file.rawWrite((&b)[0 .. T.sizeof]);
                    }
                    else
                    {
                        _file.rawWrite((&datum)[0 .. T.sizeof]);
                    }
                }
            }
        }

        static foreach (i, m; EnumMembers!RecordTag)
        {
            if (i == key)
            {
                mixin("enum memberName = __traits(identifier, EnumMembers!RecordTag[i]);");
                mixin("enum attrs = __traits(getAttributes, RecordTag." ~ to!string(
                        memberName) ~ ");");
                static assert(attrs.length == 1,
                        "Missing validation tag for RecordTag." ~ to!string(memberName));

                switch (attrs[0])
                {

                    /* Handle string */
                case RecordType.String:
                    assert(typeid(datum) == typeid(string),
                            "addRecord(RecordTag." ~ memberName ~ ") expects string, not " ~ typeof(datum)
                            .stringof);
                    writeln("Writing key: ", key, " - value: ", datum);
                    encoder = &encodeString;
                    break;

                case RecordType.Int8:
                    assert(typeid(datum) == typeid(int8_t),
                            "addRecord(RecordTag." ~ memberName ~ ") expects int8_t, not " ~ typeof(datum)
                            .stringof);
                    writeln("Writing key: ", key, " - value: ", datum);
                    record.type = RecordType.Int8;
                    encoder = &encodeNumeric;
                    break;
                case RecordType.Uint8:
                    assert(typeid(datum) == typeid(uint8_t),
                            "addRecord(RecordTag." ~ memberName ~ ") expects uint8_t, not " ~ typeof(datum)
                            .stringof);
                    writeln("Writing key: ", key, " - value: ", datum);
                    record.type = RecordType.Uint8;
                    encoder = &encodeNumeric;
                    break;

                case RecordType.Int16:
                    assert(typeid(datum) == typeid(int16_t),
                            "addRecord(RecordTag." ~ memberName ~ ") expects int16_t, not " ~ typeof(datum)
                            .stringof);
                    writeln("Writing key: ", key, " - value: ", datum);
                    record.type = RecordType.Int16;
                    encoder = &encodeNumeric;
                    break;
                case RecordType.Uint16:
                    assert(typeid(datum) == typeid(uint16_t),
                            "addRecord(RecordTag." ~ memberName ~ ") expects uint16_t, not " ~ typeof(datum)
                            .stringof);
                    writeln("Writing key: ", key, " - value: ", datum);
                    record.type = RecordType.Uint16;
                    encoder = &encodeNumeric;
                    break;
                case RecordType.Int32:
                    assert(typeid(datum) == typeid(int32_t),
                            "addRecord(RecordTag." ~ memberName ~ ") expects int32_t, not " ~ typeof(datum)
                            .stringof);
                    writeln("Writing key: ", key, " - value: ", datum);
                    record.type = RecordType.Int32;
                    encoder = &encodeNumeric;
                    break;
                case RecordType.Uint32:
                    assert(typeid(datum) == typeid(uint32_t),
                            "addRecord(RecordTag." ~ memberName ~ ") expects uint32_t, not " ~ typeof(datum)
                            .stringof);
                    writeln("Writing key: ", key, " - value: ", datum);
                    record.type = RecordType.Uint32;
                    encoder = &encodeNumeric;
                    break;
                case RecordType.Int64:
                    assert(typeid(datum) == typeid(int64_t),
                            "addRecord(RecordTag." ~ memberName ~ ") expects int64_t, not " ~ typeof(datum)
                            .stringof);
                    writeln("Writing key: ", key, " - value: ", datum);
                    record.type = RecordType.Int64;
                    encoder = &encodeNumeric;
                    break;
                case RecordType.Uint64:
                    assert(typeid(datum) == typeid(uint64_t),
                            "addRecord(RecordTag." ~ memberName ~ ") expects uint64_t, not " ~ typeof(datum)
                            .stringof);
                    writeln("Writing key: ", key, " - value: ", datum);
                    record.type = RecordType.Uint64;
                    encoder = &encodeNumeric;
                    break;
                default:
                    assert(0, "INCOMPLETE SUPPORT");
                }
            }
        }

        record.tag = key;

        /* Insert the header now, we'll rewind and fix number of records */
        _file.rawWrite((&record)[0 .. Record.sizeof]);

        assert(encoder !is null, "Missing encoder");
        encoder();
    }
}