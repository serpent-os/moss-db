/*
 * SPDX-FileCopyrightText: Copyright © 2020-2022 Serpent OS Developers
 *
 * SPDX-License-Identifier: Zlib
 */

/**
 * moss.db.keyvalue.orm.save;
 *
 * Save support for the ORM API
 *
 * Authors: Copyright © 2020-2022 Serpent OS Developers
 * License: Zlib
 */

module moss.db.keyvalue.orm.save;

public import moss.db.keyvalue.errors;
public import moss.db.keyvalue.interfaces;
public import moss.db.keyvalue.orm.types;

import moss.db.keyvalue.orm.load;

import std.traits;

/**
 * Save the object in the current transaction
 *
 * Params:
 *      M = Model
 *      obj = Model object
 *      tx = Read-write transaction
 * Returns: A nullable error
 */
public DatabaseResult save(M)(scope return ref M obj, scope return Transaction tx) @safe
        if (isValidModel!M)
{
    auto rowID = rowName(obj);
    mixin("auto pkey = obj." ~ getSymbolsByUDA!(M, PrimaryKey)[0].stringof ~ ";");
    Unconst!M oldObj = Unconst!M.init;
    bool haveOldData;

    /* Does it already exist? */
    {
        immutable err = oldObj.load(tx, pkey);
        if (err.isNull)
        {
            haveOldData = true;
        }
    }

    /* Ensure the *model bucket* exists */
    immutable auto modelBucket = tx.bucket(modelName!M);
    if (modelBucket.isNull)
    {
        return DatabaseResult(DatabaseError(DatabaseErrorCode.BucketNotFound,
                M.stringof ~ ".save(): Create the model first!"));
    }

    /* Stash in the primary index */
    {
        auto err = tx.set(modelBucket, pkey.mossEncode, rowID);
        if (!err.isNull)
        {
            return err;
        }
    }

    /**
     * Now save all of the fields
     */
    return tx.createBucketIfNotExists(rowID)
        .match!((DatabaseError err) => DatabaseResult(err), (Bucket itemBucket) {
            /* Encode all the fields */
            static foreach (field; __traits(allMembers, M))
            {
                static if (__traits(compiles, __traits(getMember, obj, field)))
                {
                    {
                        /* To access UDAs on each field we have to import it. */
                        mixin("import " ~ moduleName!M ~ " : " ~ Unconst!(OriginalType!M)
                            .stringof ~ ";");

                        alias fieldType = getFieldType!(M, field);
                        static if (isEncodableSlice!fieldType && !isFieldIndexed!(M, field))
                        {
                            /* Handle encoding of slices */
                            auto name = sliceName!(M, field)(obj);

                            /* Wipe last one if it exists.. */
                            auto oldBucket = tx.bucket(name);
                            if (!oldBucket.isNull)
                            {
                                auto err = tx.removeBucket(oldBucket);
                                if (!err.isNull)
                                {
                                    return err;
                                }
                            }

                            /* Create the new bucket for slice storage */
                            auto err = tx.createBucket(name)
                                .match!((DatabaseError err) => DatabaseResult(err), (Bucket bk) {
                                    DatabaseError err;
                                    static auto val = (cast(ushort) 1).mossEncode;
                                    /* Store all the elements as *keys* which will always dedupe the list. */
                                    foreach (immutable element; __traits(getMember, obj, field))
                                    {
                                        auto res = tx.set(bk, element.mossEncode, val);
                                        if (!res.isNull)
                                        {
                                            err = res.get;
                                            break;
                                        }
                                    }
                                    return DatabaseResult(err);
                                });
                            if (!err.isNull)
                            {
                                return err;
                            }

                        }
                        else
                        {
                            /* Handle everything else */
                            immutable auto key = field.mossEncode;
                            immutable auto val = __traits(getMember, obj, field).mossEncode;

                            DatabaseResult err = tx.set(itemBucket, key, val);
                            if (!err.isNull)
                            {
                                return err;
                            }

                            /* Is this one indexed? */
                            static if (isFieldIndexed!(M, field))
                            {
                                {
                                    auto bucket = tx.bucket(indexName!(M, field));
                                    if (bucket.isNull)
                                    {
                                        return DatabaseResult(DatabaseError(DatabaseErrorCode.BucketNotFound,
                                            M.stringof ~ ".save(): Create the model first!"));
                                    }
                                    /* Remove the old index now */
                                    if (haveOldData)
                                    {
                                        immutable oldVal = __traits(getMember, oldObj, field)
                                            .mossEncode;
                                        cast(void) tx.remove(bucket, oldVal);
                                    }
                                    /* Set the new index */
                                    auto e = tx.set(bucket, val, pkey.mossEncode);
                                    if (!e.isNull)
                                    {
                                        return e;
                                    }
                                }
                            }
                        }
                    }
                }
            }

            return NoDatabaseError;
        });
}
