-- Luje
-- © 2013 David Given
-- This file is redistributable under the terms of the
-- New BSD License. Please see the COPYING file in the
-- project root for the full text.

local Utils = require("Utils")
local dbg = Utils.Debug
local pretty = require("pl.pretty")
local string_byte = string.byte
local table_concat = table.concat

local function compile_method(class, analysis, mimpl)
	local bytecode = mimpl.Code.Bytecode
	local pos = 0
	local sp = 0
	local stacksize = {}
	local output = {}
	local constants = {}

	local function b()
		pos = pos + 1 -- increment first to apply +1 offset
		return string_byte(bytecode, pos)
	end

	local function u2()
		return b()*0x100 + b()
	end

	local function u4(n)
		return u2()*0x10000 + u2()
	end

	local function checkstack(pc)
		local csp = stacksize[pc]
		if (csp == nil) then
			stacksize[pc] = sp
		else
			if (csp ~= sp) then
				Utils.Throw("stack mismatch (is currently "..sp..", but should be "..csp)
			end
		end
	end

	local function emitnonl(...)
		local args = {...}
		local argslen = select("#", ...)
		for i = 1, argslen do
			output[#output+1] = tostring(args[i])
		end
	end

	local function emit(...)
		emitnonl(...)
		output[#output+1] = "\n"
	end

	-- Add a constant to the (internal, per-method) constant pool.

	local function constant(c)
		assert(type(c) == "table")
		local n = constants[c]
		if n then
			return n
		end

		constants[#constants+1] = c
		n = "constant"..#constants
		constants[c] = n
		return n
	end

	-- Declare the variables we're going to put our stack and locals in.

	for i = 1, mimpl.Code.MaxStack do
		emit("local stack", i-1)
	end

	for i = 1, mimpl.Code.MaxLocals do
		emit("local local", i-1)
	end

	-- This table expands all the opcodes.

	local opcodemap = {
		[0x01] = function() -- aconst_null
			emit("stack", sp, " = nil")
			sp = sp + 1
		end,

		[0x02] = function() -- iconst_m1
			emit("stack", sp, " = -1")
			sp = sp + 1
		end,

		[0x03] = function() -- iconst_0
			emit("stack", sp, " = 0")
			sp = sp + 1
		end,

		[0x04] = function() -- iconst_1
			emit("stack", sp, " = 1")
			sp = sp + 1
		end,

		[0x05] = function() -- iconst_2
			emit("stack", sp, " = 2")
			sp = sp + 1
		end,

		[0x06] = function() -- iconst_3
			emit("stack", sp, " = 3")
			sp = sp + 1
		end,

		[0x07] = function() -- iconst_4
			emit("stack", sp, " = 4")
			sp = sp + 1
		end,

		[0x08] = function() -- iconst_5
			emit("stack", sp, " = 5")
			sp = sp + 1
		end,

		[0x09] = function() -- lconst_0
			emit("stack", sp, " = 0")
			sp = sp + 2
		end,

		[0x0a] = function() -- lconst_1
			emit("stack", sp, " = 1")
			sp = sp + 2
		end,

		[0x12] = function() -- ldc
			local i = b()
			local c = analysis.SimpleConstants[i]
			if (type(c) == "table") then
				c = constant(c)
			end
			emit("stack", sp, " = ", c)
			sp = sp + 1
		end,

		[0x1e] = function() -- lload_0
			emit("stack", sp, " = local0")
			sp = sp + 2
		end,

		[0x1f] = function() -- lload_1
			emit("stack", sp, " = local1")
			sp = sp + 2
		end,

		[0x20] = function() -- lload_2
			emit("stack", sp, " = local2")
			sp = sp + 2
		end,

		[0x21] = function() -- lload_3
			emit("stack", sp, " = local3")
			sp = sp + 2
		end,

		[0x2a] = function() -- aload_0
			emit("stack", sp, " = local0")
			sp = sp + 1
		end,

		[0x2b] = function() -- aload_1
			emit("stack", sp, " = local1")
			sp = sp + 1
		end,

		[0x2c] = function() -- aload_2
			emit("stack", sp, " = local2")
			sp = sp + 1
		end,

		[0x2d] = function() -- aload_3
			emit("stack", sp, " = local3")
			sp = sp + 1
		end,

		[0x3f] = function() -- lstore_0
			sp = sp - 2
			emit("local0 = stack", sp)
		end,

		[0x40] = function() -- lstore_1
			sp = sp - 2
			emit("local1 = stack", sp)
		end,

		[0x41] = function() -- lstore_2
			sp = sp - 2
			emit("local2 = stack", sp)
		end,

		[0x42] = function() -- lstore_3
			sp = sp - 2
			emit("local3 = stack", sp)
		end,

		[0x60] = function() -- iadd
			emit("stack", sp-2, " = stack", sp-2, " + stack", sp-1)
			sp = sp - 1
		end,

		[0x85] = function() -- i2l
			emit("-- i2l stack", sp-1)
			sp = sp + 1
		end,

		[0x88] = function() -- l2i
			emit("stack", sp-2, " = bit.and(stack", sp-2, ", 0xffffffff)")
			sp = sp - 1
		end,

		[0xb1] = function() -- return
			emit("do return end")
			sp = 0
		end,

		[0xb3] = function() -- putstatic
			local i = u2()
			local f = analysis.RefConstants[i]
			local c = constant(class:ClassLoader():LoadClass(f.Class))

			sp = sp - 1
			emit(c, ".fs_", f.Name, " = stack", sp)
		end,

		[0xb2] = function() -- getstatic
			local i = u2()
			local f = analysis.RefConstants[i]
			local c = constant(class:ClassLoader():LoadClass(f.Class))

			emit("stack", sp, " = ", c, ".fs_", f.Name)
			sp = sp + 1
		end,

		[0xb6] = function() -- invokevirtual
			local i = u2()
			local f = analysis.RefConstants[i]
			local c = constant(class:ClassLoader():LoadClass(f.Class))

			pretty.dump(f)
			emit("-- invokevirtual")
		end,

		[0xb8] = function() -- invokestatic
			local i = u2()
			local f = analysis.RefConstants[i]
			local c = constant(class:ClassLoader():LoadClass(f.Class))

			emitnonl("local r, e = ", c, "['m_", f.Name, f.Descriptor, "'](")

			local numinparams = #f.InParams
			local inparams = {}
			for n, d in ipairs(f.InParams) do
				sp = sp - d
				inparams[numinparams - n + 1] = "stack"..sp
			end

			emitnonl(table_concat(inparams, ", "))
			emit(")")

			if (f.OutParams > 0) then
				emit("stack", sp, " = r")
				sp = sp + f.OutParams
			end
		end,
	}

	while (pos < #bytecode) do
		checkstack(pos)
		output[#output+1] = "::pc_"..pos..":: "

		local opcode = b()
		local opcodec = opcodemap[opcode]
		if not opcodec then
			Utils.Throw("unimplemented opcode 0x"..string.format("%02x", opcode))
		end
		opcodec()
	end

	dbg(table.concat(output))
	return output
end

local function compile_static_method(class, analysis, mimpl)
	return compile_method(class, analysis, mimpl)
end

return function(classloader)
	local analysis
	local compiledMethods = {}

	local c = {
		Init = function(self, a)
			analysis = a
		end,

		ClassLoader = function(self)
			return classloader
		end,

		FindStaticMethod = function(self, n)
			local m = compiledMethods[n]
			if m then
				return m
			end

			local mimpl = analysis.Methods[n]
			m = compile_static_method(self, analysis, mimpl)
			compiledMethods[n] = m
			return m
		end
	}

	return c
end
