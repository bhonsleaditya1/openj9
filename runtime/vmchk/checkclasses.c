/*******************************************************************************
 * Copyright (c) 1991, 2021 IBM Corp. and others
 *
 * This program and the accompanying materials are made available under
 * the terms of the Eclipse Public License 2.0 which accompanies this
 * distribution and is available at https://www.eclipse.org/legal/epl-2.0/
 * or the Apache License, Version 2.0 which accompanies this distribution and
 * is available at https://www.apache.org/licenses/LICENSE-2.0.
 *
 * This Source Code may also be made available under the following
 * Secondary Licenses when the conditions for such availability set
 * forth in the Eclipse Public License, v. 2.0 are satisfied: GNU
 * General Public License, version 2 with the GNU Classpath
 * Exception [1] and GNU General Public License, version 2 with the
 * OpenJDK Assembly Exception [2].
 *
 * [1] https://www.gnu.org/software/classpath/license.html
 * [2] http://openjdk.java.net/legal/assembly-exception.html
 *
 * SPDX-License-Identifier: EPL-2.0 OR Apache-2.0 OR GPL-2.0 WITH Classpath-exception-2.0 OR LicenseRef-GPL-2.0 WITH Assembly-exception
 *******************************************************************************/

/**
 * @file
 * @ingroup VMChk
 */

#include "j9.h"
#include "j9port.h"
#include "vmcheck.h"

#define J9CLASS_EYECATCHER 0x99669966

/*
 *	J9Class sanity:
 *		Eyecatcher check:
 *			Ensure J9Class->eyecatcher == 0x99669966.
 *
 *		Superclasses check:
 *			Ensure J9Class->superclasses != null unless J9Class is Object.
 *
 *		ClassObject null check:
 *			Ensure J9Class->classObject != null if (J9Class->initializeStatus == J9ClassInitSucceeded)
 *
 *		ClassLoader segment check:
 *			Ensure J9Class->classLoader->classSegments contains J9Class.
 *
 *		ConstantPool check:
 *			Ensure J9Class->ramConstantPool->ramClass is equal to the J9Class.
 *
 *		Subclass hierarchy check:
 *			Ensure subclasses can be traversed per the J9Class classDepth.
 *
 *		Obsolete class check:
 *			Ensure obsolete classes are found in the replacedClass linked list on the currentClass.
 */

static BOOLEAN verifyJ9Class(J9JavaVM *vm, J9Class *clazz, J9Class *javaLangObjectClass);
static BOOLEAN verifyObsoleteJ9Class(J9JavaVM *vm, J9Class *clazz, J9Class *javaLangObjectClass);
static BOOLEAN verifyJ9ClassHeader(J9JavaVM *vm, J9Class *clazz, J9Class *javaLangObjectClass);
static BOOLEAN verifyJ9ClassSubclassHierarchy(J9JavaVM *vm, J9Class *clazz, J9Class *javaLangObjectClass);


void
checkJ9ClassSanity(J9JavaVM *vm)
{
	UDATA count = 0;
	UDATA obsoleteCount = 0;
	J9ClassWalkState walkState;
	J9Class *clazz;
	J9JavaVM *localJavaVM = vm;
	J9Class *javaLangObjectClass;

	vmchkPrintf(vm, "  %s Checking classes>\n", VMCHECK_PREFIX);


	javaLangObjectClass = J9VMJAVALANGOBJECT_OR_NULL(localJavaVM);

	/*
	 * allClassesStartDo() walks each segment of each classloader. It doesn't rely on subclassTraversalLink.
	 */
	clazz = vm->internalVMFunctions->allClassesStartDo(&walkState, vm, NULL);
	while (NULL != clazz) {

		if (!J9_IS_CLASS_OBSOLETE(clazz)) {
			verifyJ9Class(vm, clazz, javaLangObjectClass);
		} else {
			verifyObsoleteJ9Class(vm, clazz, javaLangObjectClass);
			obsoleteCount++;
		}

		count++;
		clazz = vm->internalVMFunctions->allClassesNextDo(&walkState);
	}
	vm->internalVMFunctions->allClassesEndDo(&walkState);

	vmchkPrintf(vm, "  %s Checking %d classes (%d obsolete) done>\n", VMCHECK_PREFIX, count, obsoleteCount);
}

/* NOTE: This function should not be called on obsolete classes (will fail if obsolete). */
static BOOLEAN
verifyJ9Class(J9JavaVM *vm, J9Class *clazz, J9Class *javaLangObjectClass)
{
	BOOLEAN passed = verifyJ9ClassHeader(vm, clazz, javaLangObjectClass);
	J9ClassLoader *classLoader = clazz->classLoader;

	if (J9_ARE_ANY_BITS_SET(J9CLASS_EXTENDED_FLAGS(clazz), J9ClassIsAnonymous)) {
		classLoader = vm->anonClassLoader;
	}

	if (NULL != classLoader) {
		if (NULL == findSegmentInClassLoaderForAddress(classLoader, (U_8*)clazz)) {
			vmchkPrintf(vm, "%s - Error class=0x%p not found in classLoader=0x%p>\n",
				VMCHECK_FAILED, clazz, classLoader);
			passed = FALSE;
		}
	}

	if (!verifyJ9ClassSubclassHierarchy(vm, clazz, javaLangObjectClass)) {
		passed = FALSE;
	}

	return passed;
}

static BOOLEAN
verifyObsoleteJ9Class(J9JavaVM *vm, J9Class *clazz, J9Class *javaLangObjectClass)
{
	BOOLEAN passed = TRUE;
	J9Class *replacedClass;
	J9Class *currentClass = J9_CURRENT_CLASS(clazz);

	verifyJ9ClassHeader(vm, currentClass, javaLangObjectClass);

	replacedClass = currentClass->replacedClass;
	while (NULL != replacedClass) {
		if (replacedClass == clazz) {
			/* Expected case: found clazz in the list. */
			break;
		}
		replacedClass = replacedClass->replacedClass;
	}

	if (NULL == replacedClass) {
		vmchkPrintf(vm, "%s - Error obsolete class=0x%p is not in replaced list on currentClass=0x%p>\n",
			VMCHECK_FAILED, clazz, currentClass);
		passed = FALSE;
	}

	return passed;
}

/* NOTE: This function should not be called on obsolete classes (will fail if obsolete). */
static BOOLEAN
verifyJ9ClassHeader(J9JavaVM *vm, J9Class *clazz, J9Class *javaLangObjectClass)
{
	BOOLEAN passed = TRUE;
	J9ROMClass *romClass = clazz->romClass;
	J9ClassLoader *classLoader = clazz->classLoader;

	if (J9CLASS_EYECATCHER != clazz->eyecatcher) {
		vmchkPrintf(vm, "%s - Error 0x99669966 != eyecatcher (0x%p) for class=0x%p>\n",
			VMCHECK_FAILED, clazz->eyecatcher, clazz);
		passed = FALSE;
	}

	if (NULL == romClass) {
		vmchkPrintf(vm, "%s - Error NULL == romClass for class=0x%p>\n", VMCHECK_FAILED, clazz);
		passed = FALSE;
	}
	if (NULL == classLoader) {
		vmchkPrintf(vm, "%s - Error NULL == classLoader for class=0x%p>\n", VMCHECK_FAILED, clazz);
		passed = FALSE;
	}

	if (javaLangObjectClass != clazz) {
		if (NULL == clazz->superclasses) {
			vmchkPrintf(vm, "%s - Error NULL == superclasses for non-java.lang.Object class=0x%p>\n",
				VMCHECK_FAILED, clazz);
			passed = FALSE;
		}
	}

	if (J9ClassInitSucceeded == clazz->initializeStatus) {
		if (NULL == clazz->classObject) {
			vmchkPrintf(vm, "%s - Error NULL == class->classObject for initialized class=0x%p>\n",
				VMCHECK_FAILED, clazz);
			passed = FALSE;
		}
	}

	if (J9_IS_CLASS_OBSOLETE(clazz)) {
		vmchkPrintf(vm, "%s - Error clazz=0x%p is obsolete>\n", VMCHECK_FAILED, clazz);
		passed = FALSE;
	}

	if ((NULL != romClass) && (0 != romClass->ramConstantPoolCount)) {
		J9ConstantPool *constantPool = clazz->ramConstantPool;
		J9Class *cpClass = constantPool->ramClass;

		if (clazz != cpClass) {
			vmchkPrintf(vm, "%s - Error clazz=0x%p does not equal clazz->ramConstantPool->ramClass=0x%p>\n",
				VMCHECK_FAILED, clazz, cpClass);
			passed = FALSE;
		}
	}

	return passed;
}

static BOOLEAN 
verifyJ9ClassSubclassHierarchy(J9JavaVM *vm, J9Class *clazz, J9Class *javaLangObjectClass)
{
	UDATA index = 0;
	UDATA rootDepth = J9CLASS_DEPTH(clazz);
	J9Class *currentClass = clazz;
	BOOLEAN done = FALSE;

	while (!done) {
		J9Class *nextSubclass = currentClass->subclassTraversalLink;

		if (NULL == nextSubclass) {
			vmchkPrintf(vm, "%s - Error class=0x%p had NULL entry in subclassTraversalLink list at index=%d following class=0x%p>\n",
				VMCHECK_FAILED, clazz, index, currentClass);
			return FALSE;
		}

		/* Sanity check the nextSubclass. */
		if (!verifyJ9ClassHeader(vm, nextSubclass, javaLangObjectClass)) {
			return FALSE;
		}

		if (J9CLASS_DEPTH(nextSubclass) <= rootDepth) {
			done = TRUE;
		} else {
			currentClass = nextSubclass;
			index++;
		}
	}

	return TRUE;
}

J9MemorySegment *
findSegmentInClassLoaderForAddress(J9ClassLoader *classLoader, U_8 *address)
{
	J9MemorySegment *segment = classLoader->classSegments;

	while (NULL != segment) {
		if ((address >= segment->heapBase) && (address < segment->heapAlloc)) {
			break;
		}
		segment = segment->nextSegmentInClassLoader;
	}

	return segment;
}
