dnl Copyright (c) 1991, 2022 IBM Corp. and others
dnl
dnl This program and the accompanying materials are made available under
dnl the terms of the Eclipse Public License 2.0 which accompanies this
dnl distribution and is available at https://www.eclipse.org/legal/epl-2.0/
dnl or the Apache License, Version 2.0 which accompanies this distribution and
dnl is available at https://www.apache.org/licenses/LICENSE-2.0.
dnl
dnl This Source Code may also be made available under the following
dnl Secondary Licenses when the conditions for such availability set
dnl forth in the Eclipse Public License, v. 2.0 are satisfied: GNU
dnl General Public License, version 2 with the GNU Classpath
dnl Exception [1] and GNU General Public License, version 2 with the
dnl OpenJDK Assembly Exception [2].
dnl
dnl [1] https://www.gnu.org/software/classpath/license.html
dnl [2] http://openjdk.java.net/legal/assembly-exception.html
dnl
dnl SPDX-License-Identifier: EPL-2.0 OR Apache-2.0 OR GPL-2.0 WITH Classpath-exception-2.0 OR LicenseRef-GPL-2.0 WITH Assembly-exception

include(jilvalues.m4)

dnl for(<symbol>=<start>; <symbol> < <end>; ++<symbol>) { <expr> }
dnl $1 = symbol name
dnl $2 = starting value
dnl $3 = ending value
dnl $4 = expression
define({forloop},
	{define({$1}, {$2})$4
	ifelse({$2}, {$3}, {},{$0({$1}, incr({$2}), {$3}, {$4})})})
define({SYM_COUNT},0)
define({INC_SYM_COUNT},{define({SYM_COUNT},incr(SYM_COUNT))})

J9CONST({CINTERP_STACK_SIZE},J9TR_cframe_sizeof)

dnl Work arround for older versions of MASM which don't support AVX-512
ifdef({WIN32},{

	dnl Generate instruction of format OP <reg>, [<disp32> + rsp]
	dnl $1 - prefix
	dnl $2 - opcode
	dnl $3 - reg number
	dnl $4 - offset
	dnl low 3 bits of register number are stored in modR/M[5:3]
	define({INSTRUCTION}, {
		dnl prefix
		$1
		dnl opcode
		BYTE $2
		dnl modR/M byte
		BYTE 084h OR (($3 AND 7) SHL 3)
		dnl SIB byte
		BYTE 024h
		dnl displacement
		DWORD $4
	})

	dnl 2 byte VEX prefix
	define({VEX2},{BYTE 0c5h, 0f8h})

	dnl 3 byte VEX prefix with W bit set
	define({VEX3},{BYTE 0c4h, 0e1h, 0f8h})

	dnl EVEX prefix
	dnl $1 - register number
	dnl bits 3 and 4 of the register number are stored inverted in bits 7 and 4 in the second byte of the EVEX prefix
	define({EVEX},{
		BYTE 062h
		BYTE 061h OR ((NOT $1 AND 8) SHL 4) OR (NOT $1 AND 010h)
		BYTE 0feh, 048h
	})

	dnl $1 = register number
	dnl $2 = stack displacment
	define({SAVE_MASK_16},    {INSTRUCTION({VEX2}, 090h, {$1}, {$2})})
	define({RESTORE_MASK_16}, {INSTRUCTION({VEX2}, 091h, {$1}, {$2})})
	define({SAVE_MASK_64},    {INSTRUCTION({VEX3}, 090h, {$1}, {$2})})
	define({RESTORE_MASK_64}, {INSTRUCTION({VEX3}, 091h, {$1}, {$2})})
	define({SAVE_ZMM_REG},    {INSTRUCTION({EVEX({$1})}, 07fh, {$1}, {$2})})
	define({RESTORE_ZMM_REG}, {INSTRUCTION({EVEX({$1})}, 06fh, {$1}, {$2})})

},{ dnl WIN32
	dnl $1 = register number
	dnl $2 = stack displacment
	define({SAVE_MASK_16},    {kmovw word ptr $2[_rsp],k{}$1})
	define({RESTORE_MASK_16}, {kmovw k{}$1,word ptr $2[_rsp]})
	define({SAVE_MASK_64},    {kmovq qword ptr $2[_rsp],k{}$1})
	define({RESTORE_MASK_64}, {kmovq k{}$1,qword ptr $2[_rsp]})
	define({SAVE_ZMM_REG}, {vmovdqu64 zmmword ptr $2[_rsp],zmm{}$1})
	define({RESTORE_ZMM_REG}, {vmovdqu64 zmm{}$1,zmmword ptr $2[_rsp]})

}) dnl WIN32
ifdef({WIN32},{

define({SHORT_JMP},{short})

ifdef({ASM_J9VM_ENV_DATA64},{

define({FILE_START},{
	OPTION NOSCOPED
	_TEXT SEGMENT 'CODE'
})

},{ dnl ASM_J9VM_ENV_DATA64

define({FILE_START},{
	.686p
	assume cs:flat,ds:flat,ss:flat
	option NoOldMacros
	.xmm
	_TEXT SEGMENT PARA USE32 PUBLIC 'CODE'
})

}) dnl ASM_J9VM_ENV_DATA64

define({FILE_END},{
	_TEXT ends
	end
})

define({START_PROC},{
	align 16
	DECLARE_PUBLIC($1)
	GLOBAL_SYMBOL($1) proc
})

define({END_PROC},{$1 endp})

define({DECLARE_PUBLIC},{public $1})

define({DECLARE_EXTERN},{extrn $1:near})

define({LABEL},$1)

define({C_FUNCTION_SYMBOL},$1)

define({GLOBAL_SYMBOL},$1)

},{ dnl WIN32

ifdef({OSX},{

dnl OSX

define({SHORT_JMP},{})

define({FILE_START},{
	.intel_syntax noprefix
	.text
})

define({C_FUNCTION_SYMBOL},_$1)

define({GLOBAL_SYMBOL},_$1)

},{ dnl OSX

dnl LINUX

define({SHORT_JMP},{short})

define({FILE_START},{
	.intel_syntax noprefix
	.text
})

define({C_FUNCTION_SYMBOL},$1)

define({GLOBAL_SYMBOL},$1)

}) dnl OSX

dnl LINUX and OSX

define({START_PROC},{
	.align 16
	DECLARE_PUBLIC($1)
	GLOBAL_SYMBOL($1):
})

define({FILE_END})

define({END_PROC},{
END_$1:
ifdef({OSX},{

},{ dnl OSX
	.size $1,END_$1 - $1
}) dnl OSX
})

define({DECLARE_PUBLIC},{.global GLOBAL_SYMBOL($1)})

define({DECLARE_EXTERN},{.extern C_FUNCTION_SYMBOL($1)})

ifdef({OSX},{
define({LABEL},$1)
},{ dnl OSX
define({LABEL},.$1)
}) dnl OSX

}) dnl WIN32

ifdef({ASM_J9VM_ENV_DATA64},{
	dnl 64-bit

dnl JIT linkage:
dnl register save order in memory: RAX RBX RCX RDX RDI RSI RBP RSP R8-R15 XMM0-15
dnl argument GPRs: RAX RSI RDX RCX
dnl preserved: RBX R9-R15

define({_rax},{rax})
define({_rbx},{rbx})
define({_rcx},{rcx})
define({_rdx},{rdx})
define({_rsi},{rsi})
define({_rdi},{rdi})
define({_rsp},{rsp})
define({_rbp},{rbp})
define({uword},{qword})

ifdef({WIN32},{

dnl C linkage for windows:
dnl argument GPRs: RCX RDX R8 R9
dnl preserved: RBX RDI RSI R12-R15 XMM6-15

define({PARM_REG},{ifelse($1,1,_rcx,$1,2,_rdx,$1,3,r8,$1,4,r9,{ERROR})})

define({FASTCALL_C},{
	sub _rsp,4*J9TR_pointerSize
	CALL_C_FUNC($1,4,0)
	add _rsp,4*J9TR_pointerSize
})

define({FASTCALL_C_WITH_VMTHREAD},{
	mov _rcx,_rbp
	FASTCALL_C($1,$2)
})

define({CALL_C_WITH_VMTHREAD},{FASTCALL_C_WITH_VMTHREAD($1,$2)})

},{ dnl WIN32

dnl C linkage for linux:
dnl argument GPRs: RDI RSI RDX RCX R8 R9
dnl preserved: RBX R12-R15, no XMM

define({PARM_REG},{ifelse($1,1,_rdi,$1,2,_rsi,$1,3,_rdx,$1,4,_rcx,$1,5,r8,$1,6,r9,{ERROR})})

define({FASTCALL_C},{
	CALL_C_FUNC($1,0,0)
})

define({FASTCALL_C_WITH_VMTHREAD},{
	mov _rdi,_rbp
	FASTCALL_C($1,$2)
})

define({CALL_C_WITH_VMTHREAD},{FASTCALL_C_WITH_VMTHREAD($1,$2)})

}) dnl WIN32

},{ dnl ASM_J9VM_ENV_DATA64
	dnl 32-bit

dnl JIT linkage:
dnl register save order in memory: EAX EBX ECX EDX EDI ESI EBP ESP XMM0-7
dnl argument GPRs: none
dnl preserved: EBX ECX ESI, no XMM
dnl C linkage (windows and linux)
dnl argument GPRs: none (stdcall) / ECX EDX (fastcall)
dnl preserved: EBX EDI ESI, no XMM

define({PARM_REG},{ifelse($1,1,_rcx,$1,2,_rdx,{ERROR})})

define({_rax},{eax})
define({_rbx},{ebx})
define({_rcx},{ecx})
define({_rdx},{edx})
define({_rsi},{esi})
define({_rdi},{edi})
define({_rsp},{esp})
define({_rbp},{ebp})
define({uword},{dword})

define({FASTCALL_STACK_PARM_SLOTS},{ifelse(eval($1),0,0,eval($1),1,0,eval(($1)-2))})

ifdef({WIN32},{

define({FASTCALL_SYMBOL},{@$1@eval(($2)*4)})

define({FASTCALL_EXTERN},{extern PASCAL FASTCALL_SYMBOL($1,$2):near})

define({FASTCALL_CLEAN_STACK},{ifelse(FASTCALL_STACK_PARM_SLOTS($1),0,{},{add _rsp,4*FASTCALL_STACK_PARM_SLOTS($1)})})

},{ dnl WIN32

define({FASTCALL_CLEAN_STACK},{})

}) dnl WIN32

define({FASTCALL_C},{
	call FASTCALL_SYMBOL($1,$2)
	FASTCALL_CLEAN_STACK($2)
})

define({FASTCALL_C_WITH_VMTHREAD},{
	mov _rcx,_rbp
	CALL_C_FUNC(FASTCALL_SYMBOL($1,1),0,0)
	FASTCALL_CLEAN_STACK(1)
})

define({FASTCALL_INDIRECT_WITH_VMTHREAD},{
	mov _rcx,_rbp
	CALL_C_FUNC($1,0,0)
	FASTCALL_CLEAN_STACK(1)
})

define({CALL_C_WITH_VMTHREAD},{
dnl maintain 16-byte stack alignment
	sub esp,12
	push ebp
	CALL_C_FUNC($1,4,0)
	add esp,16
})

}) dnl ASM_J9VM_ENV_DATA64

define({SWITCH_TO_C_STACK},{
	mov uword ptr J9TR_VMThread_sp[_rbp],_rsp
	mov _rsp,uword ptr J9TR_VMThread_machineSP[_rbp]
})

define({SWITCH_TO_JAVA_STACK},{
	mov uword ptr J9TR_VMThread_machineSP[_rbp],_rsp
	mov _rsp,uword ptr J9TR_VMThread_sp[_rbp]
})

define({CALL_C_FUNC},{
	mov uword ptr (J9TR_machineSP_vmStruct+$3+(J9TR_pointerSize*$2))[_rsp],_rbp
	mov _rbp,uword ptr (J9TR_machineSP_machineBP+$3+(J9TR_pointerSize*$2))[_rsp]
	call C_FUNCTION_SYMBOL($1)
	mov _rbp,uword ptr (J9TR_machineSP_vmStruct+$3+(J9TR_pointerSize*$2))[_rsp]
})

define({J9VMTHREAD},{_rbp})
define({J9SP},{_rsp})
define({J9PC},{_rsi})
define({J9LITERALS},{_rbx})
define({J9A0},{_rcx})

dnl When entering any a JIT helper, _rbp is always the vmThread
dnl and _rsp is always the java SP, so those are ignored by the
dnl SAVE/RESTORE macros as they will never be register mapped.
dnl The exceptions to the above rule are jitAcquireVMAccess / jitReleaseVMAccess
dnl which are called with the _rbp as above, but the _rsp points to the C stack.

ifdef({ASM_J9VM_ENV_DATA64},{

define({END_HELPER},{
	ret
	END_PROC($1)
})

ifdef({WIN32},{

define({SAVE_C_VOLATILE_REGS},{
	mov qword ptr J9TR_cframe_rax[_rsp],rax
	mov qword ptr J9TR_cframe_rcx[_rsp],rcx
	mov qword ptr J9TR_cframe_rdx[_rsp],rdx
 dnl RSI not volatile in C but is a JIT helper argument register
	mov qword ptr J9TR_cframe_rsi[_rsp],rsi
	mov qword ptr J9TR_cframe_r8[_rsp],r8
	mov qword ptr J9TR_cframe_r9[_rsp],r9
	mov qword ptr J9TR_cframe_r10[_rsp],r10
	mov qword ptr J9TR_cframe_r11[_rsp],r11
ifdef({METHOD_INVOCATION},{
	movq qword ptr J9TR_cframe_jitFPRs+(0*8)[_rsp],xmm0
	movq qword ptr J9TR_cframe_jitFPRs+(1*8)[_rsp],xmm1
	movq qword ptr J9TR_cframe_jitFPRs+(2*8)[_rsp],xmm2
	movq qword ptr J9TR_cframe_jitFPRs+(3*8)[_rsp],xmm3
	movq qword ptr J9TR_cframe_jitFPRs+(4*8)[_rsp],xmm4
	movq qword ptr J9TR_cframe_jitFPRs+(5*8)[_rsp],xmm5
},{ dnl METHOD_INVOCATION
	mov r8,J9TR_VMThread_javaVM[J9VMTHREAD]
	mov r8d,J9TR_JavaVM_extendedRuntimeFlags[r8]
	test r8d,J9TR_J9_EXTENDED_RUNTIME_USE_EXTENDED_VECTOR_REGISTERS
	jnz LABEL(L_zmm_save{}SYM_COUNT)
	test r8d,J9TR_J9_EXTENDED_RUNTIME_USE_VECTOR_REGISTERS
	jz LABEL(L_xmm_save{}SYM_COUNT)

	dnl save YMM registers
	forloop({REG_CTR}, 0, 5, {vmovdqu ymmword ptr J9TR_cframe_jitFPRs+(REG_CTR*32)[_rsp],ymm{}REG_CTR})
	jmp LABEL(L_save_volatile_done{}SYM_COUNT)

	dnl save ZMM registers
	LABEL(L_zmm_save{}SYM_COUNT):
	forloop({REG_CTR}, 0, 5, {SAVE_ZMM_REG(REG_CTR, J9TR_cframe_jitFPRs+(REG_CTR*64))})
	test r8d,J9TR_J9_EXTENDED_RUNTIME_USE_VECTOR_REGISTERS
	jnz LABEL(L_avx_512bw_save{}SYM_COUNT)

	forloop({REG_CTR}, 0, 7, {SAVE_MASK_16(REG_CTR, J9TR_cframe_maskRegisters+(REG_CTR*2))})
	jmp LABEL(L_save_volatile_done{}SYM_COUNT)

	LABEL(L_avx_512bw_save{}SYM_COUNT):
	forloop({REG_CTR}, 0, 7, {SAVE_MASK_64(REG_CTR, J9TR_cframe_maskRegisters+(REG_CTR*8))})
	jmp LABEL(L_save_volatile_done{}SYM_COUNT)

	dnl save XMM registers
	LABEL(L_xmm_save{}SYM_COUNT):
	movdqa J9TR_cframe_jitFPRs+(0*16)[_rsp],xmm0
	movdqa J9TR_cframe_jitFPRs+(1*16)[_rsp],xmm1
	movdqa J9TR_cframe_jitFPRs+(2*16)[_rsp],xmm2
	movdqa J9TR_cframe_jitFPRs+(3*16)[_rsp],xmm3
	movdqa J9TR_cframe_jitFPRs+(4*16)[_rsp],xmm4
	movdqa J9TR_cframe_jitFPRs+(5*16)[_rsp],xmm5

	LABEL(L_save_volatile_done{}SYM_COUNT):
	INC_SYM_COUNT()
}) dnl METHOD_INVOCATION
})

define({RESTORE_C_VOLATILE_REGS},{
ifdef({METHOD_INVOCATION},{
	movq xmm0,qword ptr J9TR_cframe_jitFPRs+(0*8)[_rsp]
	movq xmm1,qword ptr J9TR_cframe_jitFPRs+(1*8)[_rsp]
	movq xmm2,qword ptr J9TR_cframe_jitFPRs+(2*8)[_rsp]
	movq xmm3,qword ptr J9TR_cframe_jitFPRs+(3*8)[_rsp]
	movq xmm4,qword ptr J9TR_cframe_jitFPRs+(4*8)[_rsp]
	movq xmm5,qword ptr J9TR_cframe_jitFPRs+(5*8)[_rsp]
},{ dnl METHOD_INVOCATION
	dnl J9TR_J9_EXTENDED_RUNTIME_USE_VECTOR_REGISTERS marks if we are using AVX-2 (eg YMM)
	dnl J9TR_J9_EXTENDED_RUNTIME_USE_EXTENDED_VECTOR_REGISTERS marks if we are using AVX-512 (eg ZMM)
	dnl No flags means normal SSE registers (XMM)
	mov r8,J9TR_VMThread_javaVM[J9VMTHREAD]
	mov r8d,J9TR_JavaVM_extendedRuntimeFlags[r8]
	test r8d,J9TR_J9_EXTENDED_RUNTIME_USE_EXTENDED_VECTOR_REGISTERS
	jnz LABEL(L_zmm_restore{}SYM_COUNT)
	test r8d,J9TR_J9_EXTENDED_RUNTIME_USE_VECTOR_REGISTERS
	jz LABEL(L_xmm_restore{}SYM_COUNT)

	dnl restore YMM registers
	forloop({REG_CTR}, 0, 5, {vmovdqu ymm{}REG_CTR,ymmword ptr J9TR_cframe_jitFPRs+(REG_CTR*32)[_rsp]})
	jmp LABEL(L_restore_volatile_done{}SYM_COUNT)

	dnl restore ZMM registers
	LABEL(L_zmm_restore{}SYM_COUNT):
	forloop({REG_CTR}, 0, 5, {RESTORE_ZMM_REG(REG_CTR, J9TR_cframe_jitFPRs+(REG_CTR*64))})
	test r8d,J9TR_J9_EXTENDED_RUNTIME_USE_VECTOR_REGISTERS
	jnz LABEL(L_avx_512bw_restore{}SYM_COUNT)

	forloop({REG_CTR}, 0, 7, {RESTORE_MASK_16(REG_CTR, J9TR_cframe_maskRegisters+(REG_CTR*2))})
	jmp LABEL(L_restore_volatile_done{}SYM_COUNT)

	LABEL(L_avx_512bw_restore{}SYM_COUNT):
	forloop({REG_CTR}, 0, 7, {RESTORE_MASK_64(REG_CTR, J9TR_cframe_maskRegisters+(REG_CTR*8))})
	jmp LABEL(L_restore_volatile_done{}SYM_COUNT)

	dnl restore XMM registers
	LABEL(L_xmm_restore{}SYM_COUNT):
	movdqa xmm0,J9TR_cframe_jitFPRs+(0*16)[_rsp]
	movdqa xmm1,J9TR_cframe_jitFPRs+(1*16)[_rsp]
	movdqa xmm2,J9TR_cframe_jitFPRs+(2*16)[_rsp]
	movdqa xmm3,J9TR_cframe_jitFPRs+(3*16)[_rsp]
	movdqa xmm4,J9TR_cframe_jitFPRs+(4*16)[_rsp]
	movdqa xmm5,J9TR_cframe_jitFPRs+(5*16)[_rsp]
	LABEL(L_restore_volatile_done{}SYM_COUNT):
	INC_SYM_COUNT()
}) dnl METHOD_INVOCATION
	mov rax,qword ptr J9TR_cframe_rax[_rsp]
	mov rcx,qword ptr J9TR_cframe_rcx[_rsp]
	mov rdx,qword ptr J9TR_cframe_rdx[_rsp]
	mov r8,qword ptr J9TR_cframe_r8[_rsp]
	mov r9,qword ptr J9TR_cframe_r9[_rsp]
	mov r10,qword ptr J9TR_cframe_r10[_rsp]
	mov r11,qword ptr J9TR_cframe_r11[_rsp]
})

dnl No need to save/restore xmm8-15 - the stack walker will never need to read
dnl or modify them (no preserved FPRs in the JIT private linkage).  xmm6-7
dnl are preserved as they are JIT FP arguments which may need to be read
dnl in order to decompile.  They do not need to be restored.
dnl For the old-style dual mode helper case, RSI has already been saved,
dnl but this macro may be used without having preserved the volatile
dnl registers, so save it again here just in case.  As this is the slow path
dnl anyway, there will be no performance issue.

define({SAVE_C_NONVOLATILE_REGS},{
	mov qword ptr J9TR_cframe_rbx[_rsp],rbx
	mov qword ptr J9TR_cframe_rdi[_rsp],rdi
	mov qword ptr J9TR_cframe_rsi[_rsp],rsi
	mov qword ptr J9TR_cframe_r12[_rsp],r12
	mov qword ptr J9TR_cframe_r13[_rsp],r13
	mov qword ptr J9TR_cframe_r14[_rsp],r14
	mov qword ptr J9TR_cframe_r15[_rsp],r15
ifdef({METHOD_INVOCATION},{
dnl xmm6-7 are preserved as they are JIT FP arguments which may need
dnl to be read in order to decompile.  They do not need to be restored.
	movq qword ptr J9TR_cframe_jitFPRs+(6*8)[_rsp],xmm6
	movq qword ptr J9TR_cframe_jitFPRs+(7*8)[_rsp],xmm7
}) dnl METHOD_INVOCATION
})

define({RESTORE_C_NONVOLATILE_REGS},{
	mov rbx,qword ptr J9TR_cframe_rbx[_rsp]
	mov rdi,qword ptr J9TR_cframe_rdi[_rsp]
	mov rsi,qword ptr J9TR_cframe_rsi[_rsp]
	mov r12,qword ptr J9TR_cframe_r12[_rsp]
	mov r13,qword ptr J9TR_cframe_r13[_rsp]
	mov r14,qword ptr J9TR_cframe_r14[_rsp]
	mov r15,qword ptr J9TR_cframe_r15[_rsp]
})

},{ dnl WIN32

define({SAVE_C_VOLATILE_REGS},{
	mov qword ptr J9TR_cframe_rax[_rsp],rax
	mov qword ptr J9TR_cframe_rcx[_rsp],rcx
	mov qword ptr J9TR_cframe_rdx[_rsp],rdx
	mov qword ptr J9TR_cframe_rdi[_rsp],rdi
	mov qword ptr J9TR_cframe_rsi[_rsp],rsi
	mov qword ptr J9TR_cframe_r8[_rsp],r8
	mov qword ptr J9TR_cframe_r9[_rsp],r9
	mov qword ptr J9TR_cframe_r10[_rsp],r10
	mov qword ptr J9TR_cframe_r11[_rsp],r11
ifdef({METHOD_INVOCATION},{
	movq qword ptr J9TR_cframe_jitFPRs+(0*8)[_rsp],xmm0
	movq qword ptr J9TR_cframe_jitFPRs+(1*8)[_rsp],xmm1
	movq qword ptr J9TR_cframe_jitFPRs+(2*8)[_rsp],xmm2
	movq qword ptr J9TR_cframe_jitFPRs+(3*8)[_rsp],xmm3
	movq qword ptr J9TR_cframe_jitFPRs+(4*8)[_rsp],xmm4
	movq qword ptr J9TR_cframe_jitFPRs+(5*8)[_rsp],xmm5
	movq qword ptr J9TR_cframe_jitFPRs+(6*8)[_rsp],xmm6
	movq qword ptr J9TR_cframe_jitFPRs+(7*8)[_rsp],xmm7
},{ dnl METHOD_INVOCATION
	dnl J9TR_J9_EXTENDED_RUNTIME_USE_VECTOR_REGISTERS marks if we are using AVX-2 (eg YMM)
	dnl J9TR_J9_EXTENDED_RUNTIME_USE_EXTENDED_VECTOR_REGISTERS marks if we are using AVX-512 (eg ZMM)
	dnl No flags means normal SSE registers (XMM)
	mov r8,J9TR_VMThread_javaVM[J9VMTHREAD]
	mov r8d,J9TR_JavaVM_extendedRuntimeFlags[r8]
	test r8d,J9TR_J9_EXTENDED_RUNTIME_USE_EXTENDED_VECTOR_REGISTERS
	jnz LABEL(L_zmm_save{}SYM_COUNT)
	test r8d,J9TR_J9_EXTENDED_RUNTIME_USE_VECTOR_REGISTERS
	jz LABEL(L_xmm_save{}SYM_COUNT)

	dnl save YMM registers
	forloop({REG_CTR}, 0, 15, {vmovdqu ymmword ptr J9TR_cframe_jitFPRs+(REG_CTR*32)[_rsp],ymm{}REG_CTR})
	jmp LABEL(L_save_volatile_done{}SYM_COUNT)

	dnl save ZMM registers
	LABEL(L_zmm_save{}SYM_COUNT):
	forloop({REG_CTR}, 0, 31, {SAVE_ZMM_REG(REG_CTR, J9TR_cframe_jitFPRs+(REG_CTR*64))})
	test r8d,J9TR_J9_EXTENDED_RUNTIME_USE_VECTOR_REGISTERS
	jnz LABEL(L_avx_512bw_save{}SYM_COUNT)

	forloop({REG_CTR}, 0, 7, {SAVE_MASK_16(REG_CTR, J9TR_cframe_maskRegisters+(REG_CTR*2))})
	jmp LABEL(L_save_volatile_done{}SYM_COUNT)

	LABEL(L_avx_512bw_save{}SYM_COUNT):
	forloop({REG_CTR}, 0, 7, {SAVE_MASK_64(REG_CTR, J9TR_cframe_maskRegisters+(REG_CTR*8))})
	jmp LABEL(L_save_volatile_done{}SYM_COUNT)

	dnl save XMM registers
	LABEL(L_xmm_save{}SYM_COUNT):
	movdqa J9TR_cframe_jitFPRs+(0*16)[_rsp],xmm0
	movdqa J9TR_cframe_jitFPRs+(1*16)[_rsp],xmm1
	movdqa J9TR_cframe_jitFPRs+(2*16)[_rsp],xmm2
	movdqa J9TR_cframe_jitFPRs+(3*16)[_rsp],xmm3
	movdqa J9TR_cframe_jitFPRs+(4*16)[_rsp],xmm4
	movdqa J9TR_cframe_jitFPRs+(5*16)[_rsp],xmm5
	movdqa J9TR_cframe_jitFPRs+(6*16)[_rsp],xmm6
	movdqa J9TR_cframe_jitFPRs+(7*16)[_rsp],xmm7
	movdqa J9TR_cframe_jitFPRs+(8*16)[_rsp],xmm8
	movdqa J9TR_cframe_jitFPRs+(9*16)[_rsp],xmm9
	movdqa J9TR_cframe_jitFPRs+(10*16)[_rsp],xmm10
	movdqa J9TR_cframe_jitFPRs+(11*16)[_rsp],xmm11
	movdqa J9TR_cframe_jitFPRs+(12*16)[_rsp],xmm12
	movdqa J9TR_cframe_jitFPRs+(13*16)[_rsp],xmm13
	movdqa J9TR_cframe_jitFPRs+(14*16)[_rsp],xmm14
	movdqa J9TR_cframe_jitFPRs+(15*16)[_rsp],xmm15

	LABEL(L_save_volatile_done{}SYM_COUNT):
	INC_SYM_COUNT()
}) dnl METHOD_INVOCATION
})

define({RESTORE_C_VOLATILE_REGS},{
ifdef({METHOD_INVOCATION},{
	movq xmm0,qword ptr J9TR_cframe_jitFPRs+(0*8)[_rsp]
	movq xmm1,qword ptr J9TR_cframe_jitFPRs+(1*8)[_rsp]
	movq xmm2,qword ptr J9TR_cframe_jitFPRs+(2*8)[_rsp]
	movq xmm3,qword ptr J9TR_cframe_jitFPRs+(3*8)[_rsp]
	movq xmm4,qword ptr J9TR_cframe_jitFPRs+(4*8)[_rsp]
	movq xmm5,qword ptr J9TR_cframe_jitFPRs+(5*8)[_rsp]
	movq xmm6,qword ptr J9TR_cframe_jitFPRs+(6*8)[_rsp]
	movq xmm7,qword ptr J9TR_cframe_jitFPRs+(7*8)[_rsp]
},{ dnl METHOD_INVOCATION

	dnl J9TR_J9_EXTENDED_RUNTIME_USE_VECTOR_REGISTERS marks if we are using AVX-2 (eg YMM)
	dnl J9TR_J9_EXTENDED_RUNTIME_USE_EXTENDED_VECTOR_REGISTERS marks if we are using AVX-512 (eg ZMM)
	dnl No flags means normal SSE registers (XMM)
	mov r8,J9TR_VMThread_javaVM[J9VMTHREAD]
	mov r8d,J9TR_JavaVM_extendedRuntimeFlags[r8]
	test r8d,J9TR_J9_EXTENDED_RUNTIME_USE_EXTENDED_VECTOR_REGISTERS
	jnz LABEL(L_zmm_restore{}SYM_COUNT)
	test r8d,J9TR_J9_EXTENDED_RUNTIME_USE_VECTOR_REGISTERS
	jz LABEL(L_xmm_restore{}SYM_COUNT)

	dnl restore YMM registers
	forloop({REG_CTR}, 0, 15, {vmovdqu ymm{}REG_CTR,ymmword ptr J9TR_cframe_jitFPRs+(REG_CTR*32)[_rsp]})
	jmp LABEL(L_restore_volatile_done{}SYM_COUNT)

	dnl restore ZMM registers
	LABEL(L_zmm_restore{}SYM_COUNT):
	forloop({REG_CTR}, 0, 31, {RESTORE_ZMM_REG(REG_CTR, J9TR_cframe_jitFPRs+(REG_CTR*64))})
	test r8d,J9TR_J9_EXTENDED_RUNTIME_USE_VECTOR_REGISTERS
	jnz LABEL(L_avx_512bw_restore{}SYM_COUNT)

	forloop({REG_CTR}, 0, 7, {RESTORE_MASK_16(REG_CTR, J9TR_cframe_maskRegisters+(REG_CTR*2))})
	jmp LABEL(L_restore_volatile_done{}SYM_COUNT)

	LABEL(L_avx_512bw_restore{}SYM_COUNT):
	forloop({REG_CTR}, 0, 7, {RESTORE_MASK_64(REG_CTR, J9TR_cframe_maskRegisters+(REG_CTR*8))})
	jmp LABEL(L_restore_volatile_done{}SYM_COUNT)

	dnl restore XMM registers
	LABEL(L_xmm_restore{}SYM_COUNT):
	movdqa xmm0,J9TR_cframe_jitFPRs+(0*16)[_rsp]
	movdqa xmm1,J9TR_cframe_jitFPRs+(1*16)[_rsp]
	movdqa xmm2,J9TR_cframe_jitFPRs+(2*16)[_rsp]
	movdqa xmm3,J9TR_cframe_jitFPRs+(3*16)[_rsp]
	movdqa xmm4,J9TR_cframe_jitFPRs+(4*16)[_rsp]
	movdqa xmm5,J9TR_cframe_jitFPRs+(5*16)[_rsp]
	movdqa xmm6,J9TR_cframe_jitFPRs+(6*16)[_rsp]
	movdqa xmm7,J9TR_cframe_jitFPRs+(7*16)[_rsp]
	movdqa xmm8,J9TR_cframe_jitFPRs+(8*16)[_rsp]
	movdqa xmm9,J9TR_cframe_jitFPRs+(9*16)[_rsp]
	movdqa xmm10,J9TR_cframe_jitFPRs+(10*16)[_rsp]
	movdqa xmm11,J9TR_cframe_jitFPRs+(11*16)[_rsp]
	movdqa xmm12,J9TR_cframe_jitFPRs+(12*16)[_rsp]
	movdqa xmm13,J9TR_cframe_jitFPRs+(13*16)[_rsp]
	movdqa xmm14,J9TR_cframe_jitFPRs+(14*16)[_rsp]
	movdqa xmm15,J9TR_cframe_jitFPRs+(15*16)[_rsp]

	LABEL(L_restore_volatile_done{}SYM_COUNT):
	INC_SYM_COUNT()
}) dnl METHOD_INVOCATION
	mov rax,qword ptr J9TR_cframe_rax[_rsp]
	mov rcx,qword ptr J9TR_cframe_rcx[_rsp]
	mov rdx,qword ptr J9TR_cframe_rdx[_rsp]
	mov rdi,qword ptr J9TR_cframe_rdi[_rsp]
	mov rsi,qword ptr J9TR_cframe_rsi[_rsp]
	mov r8,qword ptr J9TR_cframe_r8[_rsp]
	mov r9,qword ptr J9TR_cframe_r9[_rsp]
	mov r10,qword ptr J9TR_cframe_r10[_rsp]
	mov r11,qword ptr J9TR_cframe_r11[_rsp]
})

define({SAVE_C_NONVOLATILE_REGS},{
	mov qword ptr J9TR_cframe_rbx[_rsp],rbx
	mov qword ptr J9TR_cframe_r12[_rsp],r12
	mov qword ptr J9TR_cframe_r13[_rsp],r13
	mov qword ptr J9TR_cframe_r14[_rsp],r14
	mov qword ptr J9TR_cframe_r15[_rsp],r15
})

define({RESTORE_C_NONVOLATILE_REGS},{
	mov rbx,qword ptr J9TR_cframe_rbx[_rsp]
	mov r12,qword ptr J9TR_cframe_r12[_rsp]
	mov r13,qword ptr J9TR_cframe_r13[_rsp]
	mov r14,qword ptr J9TR_cframe_r14[_rsp]
	mov r15,qword ptr J9TR_cframe_r15[_rsp]
})

}) dnl WIN32

define({SAVE_PRESERVED_REGS},{
	mov qword ptr J9TR_cframe_rbx[_rsp],rbx
	mov qword ptr J9TR_cframe_r9[_rsp],r9
	mov qword ptr J9TR_cframe_r10[_rsp],r10
	mov qword ptr J9TR_cframe_r11[_rsp],r11
	mov qword ptr J9TR_cframe_r12[_rsp],r12
	mov qword ptr J9TR_cframe_r13[_rsp],r13
	mov qword ptr J9TR_cframe_r14[_rsp],r14
	mov qword ptr J9TR_cframe_r15[_rsp],r15
})

define({RESTORE_PRESERVED_REGS},{
	mov rbx,qword ptr J9TR_cframe_rbx[_rsp]
	mov r9,qword ptr J9TR_cframe_r9[_rsp]
	mov r10,qword ptr J9TR_cframe_r10[_rsp]
	mov r11,qword ptr J9TR_cframe_r11[_rsp]
	mov r12,qword ptr J9TR_cframe_r12[_rsp]
	mov r13,qword ptr J9TR_cframe_r13[_rsp]
	mov r14,qword ptr J9TR_cframe_r14[_rsp]
	mov r15,qword ptr J9TR_cframe_r15[_rsp]
})

define({STORE_VIRTUAL_REGISTERS},{
	mov uword ptr J9TR_VMThread_returnValue2[_rbp],_rax
	mov uword ptr J9TR_VMThread_tempSlot[_rbp],r8
})

},{ dnl ASM_J9VM_ENV_DATA64

define({END_HELPER},{
	ret J9TR_pointerSize*$2
	END_PROC($1)
})

dnl preserved: EBX EDI ESI, no XMM

define({SAVE_C_VOLATILE_REGS},{
	mov dword ptr J9TR_cframe_rax[_rsp],eax
	mov dword ptr J9TR_cframe_rcx[_rsp],ecx
	mov dword ptr J9TR_cframe_rdx[_rsp],edx
ifdef({METHOD_INVOCATION},{
dnl No FP parameter registers
},{ dnl METHOD_INVOCATION
	mov eax,dword ptr J9TR_VMThread_javaVM[J9VMTHREAD]
	mov eax,dword ptr J9TR_JavaVM_extendedRuntimeFlags[eax]
	test eax,J9TR_J9_EXTENDED_RUNTIME_USE_EXTENDED_VECTOR_REGISTERS
	jnz LABEL(L_zmm_save{}SYM_COUNT)
	test eax,J9TR_J9_EXTENDED_RUNTIME_USE_VECTOR_REGISTERS
	jz LABEL(L_xmm_save{}SYM_COUNT)

	dnl save YMM registers
	forloop({REG_CTR}, 0, 7, {vmovdqu ymmword ptr J9TR_cframe_jitFPRs+(REG_CTR*32)[_rsp],ymm{}REG_CTR})
	jmp LABEL(L_save_volatile_done{}SYM_COUNT)

	dnl save ZMM registers
	LABEL(L_zmm_save{}SYM_COUNT):
	forloop({REG_CTR}, 0, 7, {SAVE_ZMM_REG(REG_CTR, J9TR_cframe_jitFPRs+(REG_CTR*64))})
	test eax,J9TR_J9_EXTENDED_RUNTIME_USE_VECTOR_REGISTERS
	jnz LABEL(L_avx_512bw_save{}SYM_COUNT)

	forloop({REG_CTR}, 0, 7, {SAVE_MASK_16(REG_CTR, J9TR_cframe_maskRegisters+(REG_CTR*2))})
	jmp LABEL(L_save_volatile_done{}SYM_COUNT)

	LABEL(L_avx_512bw_save{}SYM_COUNT):
	forloop({REG_CTR}, 0, 7, {SAVE_MASK_64(REG_CTR, J9TR_cframe_maskRegisters+(REG_CTR*8))})
	jmp LABEL(L_save_volatile_done{}SYM_COUNT)

	dnl save XMM registers
	LABEL(L_xmm_save{}SYM_COUNT):
	movdqa J9TR_cframe_jitFPRs+(0*16)[_rsp],xmm0
	movdqa J9TR_cframe_jitFPRs+(1*16)[_rsp],xmm1
	movdqa J9TR_cframe_jitFPRs+(2*16)[_rsp],xmm2
	movdqa J9TR_cframe_jitFPRs+(3*16)[_rsp],xmm3
	movdqa J9TR_cframe_jitFPRs+(4*16)[_rsp],xmm4
	movdqa J9TR_cframe_jitFPRs+(5*16)[_rsp],xmm5
	movdqa J9TR_cframe_jitFPRs+(6*16)[_rsp],xmm6
	movdqa J9TR_cframe_jitFPRs+(7*16)[_rsp],xmm7

	LABEL(L_save_volatile_done{}SYM_COUNT):
	INC_SYM_COUNT()

	mov eax,dword ptr J9TR_cframe_rax[_rsp]
}) dnl METHOD_INVOCATION
})

define({RESTORE_C_VOLATILE_REGS},{
ifdef({METHOD_INVOCATION},{
dnl No FP parameter registers
},{ dnl METHOD_INVOCATION
	mov eax,dword ptr J9TR_VMThread_javaVM[J9VMTHREAD]
	mov eax,dword ptr J9TR_JavaVM_extendedRuntimeFlags[eax]
	test eax,J9TR_J9_EXTENDED_RUNTIME_USE_EXTENDED_VECTOR_REGISTERS
	jnz LABEL(L_zmm_restore{}SYM_COUNT)
	test eax,J9TR_J9_EXTENDED_RUNTIME_USE_VECTOR_REGISTERS
	jz LABEL(L_xmm_restore{}SYM_COUNT)

	dnl restore YMM registers
	forloop({REG_CTR}, 0, 7, {vmovdqu ymm{}REG_CTR,ymmword ptr J9TR_cframe_jitFPRs+(REG_CTR*32)[_rsp]})
	jmp LABEL(L_restore_volatile_done{}SYM_COUNT)

	dnl restore ZMM registers
	LABEL(L_zmm_restore{}SYM_COUNT):
	forloop({REG_CTR}, 0, 7, {RESTORE_ZMM_REG(REG_CTR, J9TR_cframe_jitFPRs+(REG_CTR*64))})
	test eax,J9TR_J9_EXTENDED_RUNTIME_USE_VECTOR_REGISTERS
	jnz LABEL(L_avx_512bw_restore{}SYM_COUNT)

	forloop({REG_CTR}, 0, 7, {RESTORE_MASK_16(REG_CTR, J9TR_cframe_maskRegisters+(REG_CTR*2))})
	jmp LABEL(L_restore_volatile_done{}SYM_COUNT)

	LABEL(L_avx_512bw_restore{}SYM_COUNT):
	forloop({REG_CTR}, 0, 7, {RESTORE_MASK_64(REG_CTR, J9TR_cframe_maskRegisters+(REG_CTR*8))})
	jmp LABEL(L_restore_volatile_done{}SYM_COUNT)

	LABEL(L_xmm_restore{}SYM_COUNT):
	movdqa xmm0,J9TR_cframe_jitFPRs+(0*16)[_rsp]
	movdqa xmm1,J9TR_cframe_jitFPRs+(1*16)[_rsp]
	movdqa xmm2,J9TR_cframe_jitFPRs+(2*16)[_rsp]
	movdqa xmm3,J9TR_cframe_jitFPRs+(3*16)[_rsp]
	movdqa xmm4,J9TR_cframe_jitFPRs+(4*16)[_rsp]
	movdqa xmm5,J9TR_cframe_jitFPRs+(5*16)[_rsp]
	movdqa xmm6,J9TR_cframe_jitFPRs+(6*16)[_rsp]
	movdqa xmm7,J9TR_cframe_jitFPRs+(7*16)[_rsp]

	LABEL(L_restore_volatile_done{}SYM_COUNT):
	INC_SYM_COUNT()
}) dnl METHOD_INVOCATION
	mov eax,dword ptr J9TR_cframe_rax[_rsp]
	mov ecx,dword ptr J9TR_cframe_rcx[_rsp]
	mov edx,dword ptr J9TR_cframe_rdx[_rsp]
})

define({SAVE_C_NONVOLATILE_REGS},{
	mov dword ptr J9TR_cframe_rbx[_rsp],ebx
	mov dword ptr J9TR_cframe_rdi[_rsp],edi
	mov dword ptr J9TR_cframe_rsi[_rsp],esi
})

define({RESTORE_C_NONVOLATILE_REGS},{
	mov ebx,dword ptr J9TR_cframe_rbx[_rsp]
	mov edi,dword ptr J9TR_cframe_rdi[_rsp]
	mov esi,dword ptr J9TR_cframe_rsi[_rsp]
})

define({SAVE_PRESERVED_REGS},{
	mov dword ptr J9TR_cframe_rbx[_rsp],ebx
	mov dword ptr J9TR_cframe_rcx[_rsp],ecx
	mov dword ptr J9TR_cframe_rsi[_rsp],esi
})

define({RESTORE_PRESERVED_REGS},{
	mov ebx,dword ptr J9TR_cframe_rbx[_rsp]
	mov ecx,dword ptr J9TR_cframe_rcx[_rsp]
	mov esi,dword ptr J9TR_cframe_rsi[_rsp]
})

define({STORE_VIRTUAL_REGISTERS},{
	mov uword ptr J9TR_VMThread_returnValue2[_rbp],_rax
	mov uword ptr J9TR_VMThread_tempSlot[_rbp],_rdx
})

}) dnl ASM_J9VM_ENV_DATA64

ifdef({OSX},{

define({FASTCALL_SYMBOL},{_$1})

define({FASTCALL_EXTERN},{DECLARE_EXTERN($1)})

define({CALL_C_ADDR_WITH_VMTHREAD},{
	mov _rdi,_rbp
	mov uword ptr (J9TR_machineSP_vmStruct+(J9TR_pointerSize*$2))[_rsp],_rbp
	mov _rbp,uword ptr (J9TR_machineSP_machineBP+(J9TR_pointerSize*$2))[_rsp]
	call $1
	mov _rbp,uword ptr (J9TR_machineSP_vmStruct+(J9TR_pointerSize*$2))[_rsp]
})

},{ dnl OSX

define({CALL_C_ADDR_WITH_VMTHREAD},{CALL_C_WITH_VMTHREAD($1,$2)})

}) dnl OSX

ifdef({FASTCALL_SYMBOL},,{define({FASTCALL_SYMBOL},{$1})})

ifdef({FASTCALL_INDIRECT_WITH_VMTHREAD},,{define({FASTCALL_INDIRECT_WITH_VMTHREAD},{CALL_C_WITH_VMTHREAD($1,$2)})})

ifdef({FASTCALL_EXTERN},,{define({FASTCALL_EXTERN},{DECLARE_EXTERN(FASTCALL_SYMBOL($1,$2))})})

define({SAVE_ALL_REGS},{
	SAVE_C_VOLATILE_REGS($1)
	SAVE_C_NONVOLATILE_REGS($1)
})

define({RESTORE_ALL_REGS},{
	RESTORE_C_VOLATILE_REGS($1)
	RESTORE_C_NONVOLATILE_REGS($1)
})

define({BEGIN_HELPER},{START_PROC($1)})
