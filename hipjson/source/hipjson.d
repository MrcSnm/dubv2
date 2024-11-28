module hipjson;

JSONValue parseJSON(string jsonData)
{
    return JSONValue.parse(jsonData);
}

struct JSONArray
{
	size_t length() const { return value.length; }
	private CacheArray!(JSONValue, 8) value;

	/**
	 * Small array that holds up to N members in static memory. Whenever bigger than N,
	 * uses default D dynamic array.
	 */
	private static struct CacheArray(T, size_t N)
	{
		private T[N] staticData = void;
		private T[] dynData = void;
		private size_t actualLength = void;

		this(T[] value)
		{
			this.set(value);
		}

		private void set(T[] values)
		{
			if(values.length <= N)
				staticData.ptr[0..values.length] = values[];
			else
				dynData = values.dup;
			actualLength = values.length;
		}
		private void append(T value)
		{
			append((&value)[0..1]);
		}
		private void append(T[] values)
		{
			if(actualLength + values.length <= N)
				staticData.ptr[actualLength..actualLength+values.length] = values[];
			else
			{
				import std.array:uninitializedArray;
				if(dynData is null)
				{
					dynData = uninitializedArray!(T[])(actualLength+values.length);
					dynData.ptr[0..actualLength] = staticData.ptr[0..actualLength];
				}
				else if (dynData.length < actualLength + values.length)
				{
					size_t newSize = actualLength+values.length > actualLength*2 ? actualLength+values.length : actualLength*2;
					dynData.length = newSize;
				}
				dynData.ptr[actualLength..actualLength+values.length] = values[];
			}
			actualLength+= values.length;
		}

		void trim()
		{
			if(dynData !is null)
				dynData.length = actualLength;
		}
		size_t length() const { return actualLength; }
		inout(T)[] getArray() inout
		{
			if(actualLength <= N)
				return staticData[0..actualLength];
			return dynData[0..actualLength];
		}
	}

	this(JSONValue[] v)
	{
		this.value = CacheArray!(JSONValue, 8)(v);
	}

	static JSONArray* append(JSONArray* self, JSONValue v)
	{
		self.value.append(v);
		return self;
	}
	auto opOpAssign(string op, T)(T value) if(op == "~")
	{
		static if(is(T == JSONValue))
			return append(&this, value);
		else
			return append(&this, JSONValue(value));
	}
	private static JSONArray* trim(JSONArray* self)
	{
		self.value.trim();
		return self;
	}

	static JSONArray* createNew()
	{
		return new JSONArray([]);
	}

	static JSONArray* createNew(JSONValue[] data)
	{
		JSONArray* ret = new JSONArray(data);
		return ret;
	}


	JSONValue[] getArray(){return value.getArray;}
	const(JSONValue)[] getArray() const {return value.getArray;}
}
struct JSONObject
{
	JSONValue[string] value;
	alias value this;
}
private enum JSONState
{
	key,
	lookingAssignment,
	lookingForNext,
	value
}

enum JSONType
{
	bool_,
	float_,
	int_, integer = int_, uinteger = int_,
	string_, string = string_,
	array,
	object,
	null_
}

pragma(inline, true)
bool isWhitespace(char ch)
{
	switch(ch)
	{
		case ' ', '\t', '\n', '\r': return true;
		default: return false;
	}
}

pragma(inline, true) bool isNumber(char ch){return ch >= '0' && ch <= '9';}
pragma(inline, true) bool isNumeric(char ch){return (ch >= '0' && ch <= '9') || ch == '-' || ch == '.';}

struct JSONValue
{
	union JSONData{

		double _float;
		long _int;
		bool _bool;
		string _string;
		JSONObject* object;
		JSONArray* array;
	}
	JSONData data;
	string key;
	string error;
	JSONType type = JSONType.object;

	this(T)(T value)
	{
		import std.traits;
		static if(isIntegral!T)
		{
			type = JSONType.int_;
			data._int = value;
		}
		else static if(isFloatingPoint!T)
		{
			type = JSONType.float_;
			data._float = value;
		}
		else static if(is(T == bool))
		{
			type = JSONType.bool_;
			data._bool = value;
		}
		else static if(is(T == string))
		{
			type = JSONType.string_;
			data._string = value;
		}
		else static if(is(T == JSONObject*))
		{
			type = JSONType.object;
			data.object = value;
		}
		else static if(is(T == JSONArray*))
		{
			type = JSONType.array;
			data.array = value;
		}
		else static if(is(T == JSONValue[]))
		{
			data.array = JSONArray.createNew(value);
			type = JSONType.array;
		}
		else static if(is(T == JSONValue))
		{
			type = value.type;
			data = value.data;
		}
		else static if(is(T == typeof(null)))
		{
			data.object = null;
			type = JSONType.null_;
		}
		else static assert(false, "Unsupported type ", T.stringof);
	}

    int integer() const {return get!int;}
    bool boolean() const {return get!bool;}
    string str() const {return get!string;}
    ///Returns an array range.
    auto array() const
    {
		import std.exception;
        enforce(type == JSONType.array, "Tried to iterate a non array object of type "~getTypeName);
        struct JSONValueArrayIterator
        {
            private const(JSONArray*) arr;
            private size_t idx = 0;
            size_t length(){return arr.length;}
            bool empty(){return idx == arr.length;}
            void popFront(){idx++;}
            const(JSONValue) front(){return arr.getArray()[idx];}
            const(JSONValue) opIndex(size_t num){return arr.getArray()[num];}
        }
        return JSONValueArrayIterator(data.array);
    }

	ref JSONArray jsonArray()
	{
		return *data.array;
	}

	JSONValue[] array()
	{
		import std.exception;
		enforce(type == JSONType.array, "Tried to iterate a non array object of type "~getTypeName);
		return data.array.getArray();
	}

    JSONValue object() const
    {
		import std.exception;
        enforce(type == JSONType.object, "Tried to get type object but value is of type "~getTypeName);
		JSONValue ret;
		ret.data = data;
		ret.error = error;
		ret.key = key;
		ret.type = JSONType.object;
        return ret;
    }

	string[] keys()
	{
		import std.exception;
        enforce(type == JSONType.object, "Tried to get type object but value is of type "~getTypeName);
		return data.object.value.keys;
	}
	JSONValue[] values()
	{
		import std.exception;
        enforce(type == JSONType.object, "Tried to get type object but value is of type "~getTypeName);
		return data.object.value.values;
	}

	string getTypeName() const
	{
		final switch(type) with(JSONType)
		{
			case int_: return "int";
			case bool_: return "bool";
			case float_: return "float";
			case string_: return "string";
			case object: return "object";
			case array: return "array";
			case null_: return "null";
		}
	}

	T get(T)() const
	{
		import std.traits;
		import std.exception;
		static if(isIntegral!T)
		{
			enforce(type == JSONType.int_, "Tried to get type "~T.stringof~" but value is of type "~getTypeName);
			return cast(Unqual!T)data._int;
		}
		else static if(isFloatingPoint!T)
		{
			enforce(type == JSONType.float_, "Tried to get type "~T.stringof~" but value is of type "~getTypeName);
			return cast(Unqual!T)data._float;
		}
		else static if(is(T == bool))
		{
			enforce(type == JSONType.bool_, "Tried to get type "~T.stringof~" but value is of type "~getTypeName);
			return cast(Unqual!T)data._bool;
		}
		else static if(is(T == string))
		{
			enforce(type == JSONType.string_, "Tried to get type "~T.stringof~" but value is of type "~getTypeName);
			return data._string;
		}
		else static if(is(T == JSONObject))
		{
			enforce(type == JSONType.object, "Tried to get type "~T.stringof~" but value is of type "~getTypeName);
			return *data.object;
		}
		else static if(is(T == JSONArray))
		{
			enforce(type == JSONType.array, "Tried to get type "~T.stringof~" but value is of type "~getTypeName);
			return *data.array;
		}
	}
	bool isNull()
	{
		with(JSONType)
		{
			if(type == null_) return true;
			if(type == JSONType.object) return data.object == null;
			if(type == JSONType.array) return data.array == null;
		}
		return false;
	}

	static JSONValue emptyObject()
	{
		JSONValue ret;
		ret.type = JSONType.object;
		ret.data.object = new JSONObject();
		return ret;
	}
	static JSONValue emptyArray()
	{
		JSONValue ret;
		ret.type = JSONType.array;
		ret.data.array = JSONArray.createNew();
		return ret;
	}

	private static JSONValue create(T)(T data, string key)
	{
		JSONValue ret = JSONValue(data);
		ret.key = key;
		return ret;
	}
	private static JSONValue errorObj(string message)
	{
		JSONValue ret;
		ret.error = message;
		return ret;
	}


	private static JSONValue parse(string data)
	{
		import core.memory;
		import std.conv:to;

		if(!data.length)
		{
			return JSONValue.errorObj("No data provided");
		}
		ptrdiff_t index = 0;
		StringPool pool = StringPool(cast(size_t)(data.length*0.75));

		// bool getNextString(string data, ptrdiff_t currentIndex, out ptrdiff_t newIndex, out string theString)
		// {
		// 	import std.array;
		// 	assert(data[currentIndex] == '"');
		// 	ptrdiff_t i = currentIndex + 1;
		// 	size_t returnLength = 0;
		// 	// char[] ret = uninitializedArray!(char[])(128);
		// 	char[] ret = pool.getNewString(64);
		// 	char ch;

		// 	ubyte[4] chars;
		// 	bool escaped;
		// 	LOOP: while(i < data.length)
		// 	{
		// 		ubyte count = nextByte32(chars, data, i);
		// 		for(size_t byteIndex = 0; byteIndex < count; byteIndex++)
		// 		{
		// 			ch = cast(char)chars[byteIndex];
		// 			if(!escaped)
		// 			{
		// 				if(ch == '"')
		// 				{
		// 					i+= byteIndex;
		// 					break LOOP;
		// 				}
		// 				else if(ch == '\\')
		// 				{
		// 					escaped = true;
		// 					continue;
		// 				}
		// 			}
		// 			if(returnLength >= ret.length)
		// 				ret = pool.resizeString(ret, ret.length*2);
		// 			ret[returnLength++] = cast(char)chars[byteIndex];
		// 			escaped = false;
		// 		}
		// 		i+= count;
		// 	}
		// 	ret = pool.resizeString(ret, returnLength);
		// 	newIndex = i;
		// 	if(newIndex == data.length) //Not found
		// 		return false;
		// 	theString = cast(string)ret;
		// 	return true;
		// }

		bool getNextString(string data, ptrdiff_t currentIndex, out ptrdiff_t newIndex, out string theString)
		{
			assert(data[currentIndex] == '"', "getNextString must start with a quotation mark");
			ptrdiff_t i = currentIndex + 1;
			size_t returnLength = 0;
			char[] ret = pool.getNewString(64);
			char ch;

			while(i < data.length)
			{
				ch = data[i];
				switch(ch)
				{
					case '"': 
					{
						ret = pool.resizeString(ret, returnLength);
						newIndex = i;
						theString = cast(string)ret;
						return true;
					}
					case '\\':
						if(i + 1 < data.length)
						{
							i++;
							switch(data[i])
							{
								case 'n':
									ch = '\n';
									break;
								case 't':
									ch = '\t';
									break;
								case 'r':
									ch = '\r';
									break;
								default:
									ch = data[i];
									break;
							}
						}
						else
							return false;
						break;
					default: break;
				}
				if(returnLength >= ret.length)
					ret = pool.resizeString(ret, ret.length*2);
				
				ret[returnLength++] = ch;
				i++;
			}
			return false;
		}


		bool getNextNumber(string data, ptrdiff_t currentIndex, out ptrdiff_t newIndex, out JSONData theData, out JSONType type)
		{
			assert(data[currentIndex].isNumeric);
			bool hasDecimal = false;
			newIndex = currentIndex;
			if(data[currentIndex] == '-')
				newIndex++;
			if(data[newIndex] == '.')
			{
				hasDecimal = true;
				newIndex++;
			}

			while(newIndex < data.length)
			{
				if(!hasDecimal && data[newIndex] == '.')
				{
					if(!hasDecimal) hasDecimal = true;
					if(newIndex+1 < data.length) newIndex++;
				}
				if(isNumber(data[newIndex]))
					newIndex++;
				else 
					break;
			}
			if(hasDecimal)
			{
				theData._float = to!double(data[currentIndex..newIndex]);
				type = JSONType.float_;
			}
			else
			{
				theData._int = to!long(data[currentIndex..newIndex]);
				type = JSONType.int_;
			}
			//Stopped on a non number. Revert 1 step.
			newIndex--;
			return newIndex < data.length;
		}
		JSONValue ret;
		ret.type = JSONType.null_;
		JSONValue* current = &ret;
		JSONState state = JSONState.value;
		JSONValue lastValue = ret;

		import std.array;
		scope JSONValue[] stack = uninitializedArray!(JSONValue[])(128);
		scope ptrdiff_t stackLength = 0;

		size_t line = 0;
		string getErr(string err="", string f = __FILE_FULL_PATH__, size_t l = __LINE__)
		{
			return "Error at line "~line.to!string~" "~err~" on index '"~index.to!string~"' last parsed: "~lastValue.toString~" [Internal: "~f~":"~l.to!string~"]";
		}

		string lastKey;
		do
		{
			char ch = data[index];
			switch(ch)
			{
				case '\n': 
					line++;
					break;
				case '{':
				{
					if(state != JSONState.value)
						return JSONValue.errorObj(getErr());
					JSONValue obj = JSONValue.create(new JSONObject(), lastKey);
					if(!pushNewScope(obj, current, stackLength, stack))
						return JSONValue.errorObj(getErr("Could not push new scope in JSON. Only array, object or null are valid"));

					state = JSONState.key;
					break;
				}
				case '}':
					popScope(stackLength, stack, current);
					state = JSONState.lookingForNext;
					break;
				case ':':
					if(state != JSONState.lookingAssignment)
						return JSONValue.errorObj(getErr("expected key before ':'"));
					state = JSONState.value;
					break;
				case '"':
				{

					switch(state)
					{
						case JSONState.lookingForNext:
							if(current.type == JSONType.object)
								goto case JSONState.key;
							else if(current.type == JSONType.array)
								goto case JSONState.value;
							goto default;
						case JSONState.key:
						{
							assert(current.type == JSONType.object, getErr("only object can receive a key."));
							if(!getNextString(data, index, index, lastKey))
								return JSONValue.errorObj(getErr("unclosed quotes."));
							JSONValue keyJson;
							keyJson.key = lastKey;
							pushToStack(keyJson, current, lastValue);
							state = JSONState.lookingAssignment;
							break;
						}
						case JSONState.value:
						{
							string val;
							if(!getNextString(data, index, index, val))
								return JSONValue.errorObj(getErr("unclosed quotes."));
							pushToStack(JSONValue.create!string(val, lastKey), current, lastValue);
							state = JSONState.lookingForNext;
							break;
						}
						default:
							return JSONValue.errorObj(getErr("comma expected before key "~lastValue.key));
					}
					break;
				}
				case '[':
				{
					if(state != JSONState.lookingForNext && state != JSONState.value)
						return JSONValue.errorObj(getErr(" expected to be a value. "));
					if(!pushNewScope(JSONValue.create(JSONArray.createNew(), lastKey), current, stackLength, stack))
						return JSONValue.errorObj(getErr("Could not push new scope in JSON. Only array, object or null are valid"));
					state = JSONState.value;
					break;
				}
				case ']':
					if(state != JSONState.lookingForNext && state != JSONState.value)
						return JSONValue.errorObj(getErr("expected to be a value. "));
					popScope(stackLength, stack, current);
					state = JSONState.lookingForNext;
					break;
				case ',':
					if(state != JSONState.lookingForNext)
						return JSONValue.errorObj(getErr("unexpected comma. "));
					if(current.type != JSONType.object && current.type != JSONType.array)
						return JSONValue.errorObj(getErr("unexpected comma. "));

					switch(current.type) with(JSONType)
					{
						case object: state = JSONState.key; break;
						case array: state = JSONState.value; break;
						default: assert(false, "Error?");
					}
					break;
				default:
					switch(state)
					{
						case JSONState.value: //Any value
						case JSONState.lookingForNext: //Array
							if(ch.isNumeric)
							{
								if(state == JSONState.lookingForNext && current.type != JSONType.array)
									return JSONValue.errorObj(getErr("unexpected number."));
								if(!getNextNumber(data, index, index, lastValue.data, lastValue.type))
									return JSONValue.errorObj(getErr("unexpected end of file."));
								pushToStack(lastValue, current, lastValue);
								state = JSONState.lookingForNext;
							}
							else if(index + "true".length < data.length && data[index.."true".length + index] == "true")
							{
								if(state == JSONState.lookingForNext && current.type != JSONType.array)
									return JSONValue.errorObj(getErr("unexpected number."));
								pushToStack(JSONValue.create!bool(true, lastKey), current, lastValue);
								state = JSONState.lookingForNext;
							}
							else if(index + "false".length < data.length && data[index.."false".length + index] == "false")
							{
								if(state == JSONState.lookingForNext && current.type != JSONType.array)
									return JSONValue.errorObj(getErr("unexpected number."));
								pushToStack(JSONValue.create!bool(false, lastKey), current, lastValue);
								state = JSONState.lookingForNext;
							}
							else if(index + "null".length < data.length && data[index.."null".length + index] == "null")
							{
								if(state == JSONState.lookingForNext && current.type != JSONType.array)
									return JSONValue.errorObj(getErr("unexpected number."));
								pushToStack(JSONValue.create(null, lastKey), current, lastValue);
								state = JSONState.lookingForNext;
							}
							break;
						default:break;
					}
					break;
			}
			index++;
		}
		while(index < data.length && stack.length > 0);
		return ret;
	}

	const(JSONValue) opIndex(string key) const
	{
		assert(type == JSONType.object, "Can't get a member from a non object.");
		return (*data.object)[key];
	}
	JSONValue opIndex(string key)
	{
		assert(type == JSONType.object, "Can't get a member from a non object.");
		return (*data.object)[key];
	}
	JSONValue opIndexAssign(JSONValue v, string key)
	{
		import std.exception;
		enforce(type == JSONType.object, "Can't get a member from a non object.");
		enforce(data.object !is null, "Can't access a null object");
		(*data.object)[key] = v;
		v.key = key;
		return (*data.object)[key];
	}

	JSONValue opIndexAssign(T)(T value, string key) if(!is(T == JSONValue))
	{
		return opIndexAssign(JSONValue(value), key);
	}

	const(JSONValue)* opBinaryRight(string op)(string key) const
	if(op == "in")
	{
		if(type != JSONType.object)	return null;
		return key in (*data.object).value;
	}
    JSONValue* opBinaryRight(string op)(string key)
	if(op == "in")
	{
		if(type != JSONType.object)	return null;
		return key in (*data.object).value;
	}

    int opApply(scope int delegate(string key, JSONValue v) dg)
    {
        if(type != JSONType.object)
        {
            assert(false, "Can't iterate with key[string] and value[JSONValue] an object of type "~getTypeName);
        }
        int result = 0;
        foreach (k, v ; data.object.value)
        {
            result = dg(k, v);
            if (result)
                break;
        }
    
        return result;
    }
	bool hasErrorOccurred() const { return error.length != 0; }

	/**
	 *
	 * Params:
	 *   compressed = Won't include any space in the file. Also, won't escape backslash. Since the parsing works with a single backslash.
	 * this may reduce the json size, and increase the parsing speed.
	 *   selfPrintkey = Only used for objects.
	 * Returns:
	 */
	string toString(bool compressed = false)(bool selfPrintkey = false) const
	{
		if(hasErrorOccurred)
			return error;
		import std.conv:to;
		string ret;

		static string escapeCharacters(string input)
		{
			size_t length = input.length;
			foreach(ch; input)
			{
				if(ch == '\n' || ch == '\t' || ch == '\r' || ch == '"' || ch == '\\') length++;
			}
			if(length == input.length) return input;
			char[] escaped = new char[](length);
			length = 0;
			foreach(i; 0..input.length)
			{
				switch(input[i])
				{
					case '"':
						escaped[length] = '\\';
						escaped[++length] = '"';
						break;
					case '\\':
						escaped[length] = '\\';
						escaped[++length] = '\\';
						break;
					case '\n':
						escaped[length] = '\\';
						escaped[++length] = 'n';
						break;
					case '\r':
						escaped[length] = '\\';
						escaped[++length] = 'r';
						break;
					case '\t':
						escaped[length] = '\\';
						escaped[++length] = 't';
						break;
					default:
						escaped[length] = input[i];
						break;
				}
				length++;
			}
			return cast(string)escaped;
		}

		final switch ( type )
		{
			case JSONType.int_:
				ret = data._int.to!(string);
				break;
			case JSONType.float_:
				ret = data._float.to!string;
				break;
			case JSONType.bool_:
				ret = data._bool ? "true" : "false";
				break;
			case JSONType.string_:
				ret = '"'~escapeCharacters(data._string)~'"';
				break;
			case JSONType.null_:
				ret = "null";
				break;
			case JSONType.array:
			{
				ret = "[";
				bool isFirst = true;
				foreach(v; data.array.getArray)
				{
					static if(compressed)
					{
						if(!isFirst)
							ret~= ',';
					}
					else
					{
						if(!isFirst)
							ret~= ", ";
					}
					isFirst = false;
					ret~= v.toString!compressed(false);
				}
				ret~= "]";
				break;
			}
			case JSONType.object:
			{
				if(selfPrintkey)
				{
					static if(compressed)
						ret = '"'~escapeCharacters(key)~"\":";
					else
						ret = '"'~escapeCharacters(key)~"\": ";
				}
				ret~= '{';
				bool isFirst = true;
				foreach(k, v; data.object.value)
				{
					static if(compressed)
					{
						if(!isFirst)
							ret~= ',';
					}

					else
					{
						if(!isFirst)
							ret~=  ", ";
					}
					isFirst = false;
					static if(compressed)
						ret~= '"'~escapeCharacters(k)~"\":"~v.toString!compressed(false);
					else
						ret~= '"'~escapeCharacters(k)~"\" : "~v.toString!compressed(false);
				}
				ret~= '}';
				break;

			}
		}
		return ret;
	}

    void dispose()
    {
        if(type == JSONType.object)
        {
            foreach(v; data.object.value)
                v.dispose();
        }
        else if(type == JSONType.array)
        {
            foreach(v; data.array.value.getArray)
                v.dispose();
        }
        
    }
}

private struct StringPool
{
	private char[] pool;
	private size_t used;

	this(size_t size)
	{
		import std.array;
		this.pool = uninitializedArray!(char[])(size);
	}

	bool getSlice(size_t sliceSize, out char[] str)
	{
		if(used+sliceSize < pool.length)
		{
			str = pool[used..used+sliceSize];
			used+= sliceSize;
			return true;
		}
		return false;
	}

	char[] resizeString(char[] str, size_t newSize)
	{
		///Inside pool
		if(newSize == str.length) return str;
		if(pool.ptr <= str.ptr && pool.ptr + pool.length > str.ptr)
		{
			if(newSize > str.length)
			{
				if(newSize - str.length + used > pool.length)
				{
					used-= str.length;
					import std.array;
					char[] ret = uninitializedArray!(char[])(newSize);
					ret[0..str.length] = str[];
					return ret;
				}
				else
				{
					ptrdiff_t offset = str.ptr - pool.ptr;
					assert(offset > 0, " Out of bounds?");
					used+= newSize - str.length;
					return pool[cast(size_t)offset..offset+newSize];
				}
			}
			else
			{
				used-= str.length - newSize;
				return str[0..newSize];
			}
		}
		else
			str.length = newSize;
		return str;
	}

	/**
	*	If the pool is not enough, it will allocate randomly
	*/
	char[] getNewString(size_t strSize)
	{
		char[] ret;
		if(getSlice(strSize, ret))
			return ret;
		return new char[](strSize);
	}
}

pragma(inline, true)
bool pushNewScope(JSONValue val, ref JSONValue* current, ref ptrdiff_t stackLength, ref JSONValue[] stack)
{
	assert(val.type == JSONType.object || val.type == JSONType.array || val.type == JSONType.null_, "Unexpected push.");
	JSONValue* currTemp = current;

	stackLength++;
	if(stackLength > stack.length)
		stack~= val;
	else
		stack[stackLength-1] = val;

	current = &stack[stackLength-1];


	switch(currTemp.type)
	{
		case JSONType.object:
			currTemp.data.object.value[val.key] = *current;
			break;
		case JSONType.array:
			currTemp.data.array = JSONArray.append(currTemp.data.array, *current);
			break;
		case JSONType.null_:
			currTemp.type = val.type;
			currTemp.data = val.data;
			break;
		default: return false;
	}
	return true;
}


pragma(inline, true)
void popScope(ref ptrdiff_t stackLength, ref JSONValue[] stack, ref JSONValue* current)
{
	assert(stackLength > 0, "Unexpected pop.");

	stackLength--;
	if(stackLength > 0)
	{
		JSONValue* next = &stack[stackLength-1];
		if(current.type == JSONType.array)
			current.data.array = JSONArray.trim(current.data.array);
		current = next;
		import std.conv;
		assert(current.type == JSONType.object || current.type == JSONType.array, "Unexpected value in stack. (Typed "~(cast(size_t)(current.type)).to!string);
	}
}

pragma(inline, true)
void pushToStack(JSONValue val, ref JSONValue* current, ref JSONValue lastValue)
{
	switch(current.type) with(JSONType)
	{
		case object:
			current.data.object.value[val.key] = val;
			break;
		case array:
			current.data.array = JSONArray.append(current.data.array, val);
			break;
		case null_:
			*current = val;
			break;
		default: assert(false, "Unexpected stack type: "~current.getTypeName);
	}
	lastValue = val;
}


unittest
{
	assert(parseJSON(`
	{
    "name": "redub",
    "description": "Dub Based Build System, with parallelization per packages and easier to contribute",
    "authors": ["Hipreme"],
    "targetPath": "build",
    "buildOptions": [
        "debugInfo",
        "debugInfoC",
        "debugMode"
    ],
    "configurations": [
        {
            "name": "cli",
            "targetType": "executable"
        },
        {
            "name": "library",
            "targetType": "staticLibrary",
            "excludedSourceFiles": ["source/app.d"]
        }
    ],
    "license": "MIT",
    "dependencies": {
        "semver": {"path": "semver"},
        "colorize": {"path": "colorize"},
        "adv_diff": {"path": "adv_diff"},
        "hipjson": {"path": "hipjson"},
        "xxhash3": "~>0.0.5"
    }

}`)["configurations"].array.length == 2);

}

unittest
{
	enum json = `
{
    "D5F04185E96CC720": [
        [
			"First Value"
        ],
        [
			"Second Value"
        ]
    ]
}`;
	assert(parseJSON(json)["D5F04185E96CC720"].array[1].array[0].toString == `"Second Value"`);
}