/*******************************************************************************
 * Copyright (c) 2014 itemis AG (http://www.itemis.eu) and others.
 * All rights reserved. This program and the accompanying materials
 * are made available under the terms of the Eclipse Public License v1.0
 * which accompanies this distribution, and is available at
 * http://www.eclipse.org/legal/epl-v10.html
 *
 *******************************************************************************/
package org.xtext.xrobot.dsl.validation

import com.google.inject.Inject
import java.util.List
import org.eclipse.emf.ecore.EObject
import org.eclipse.emf.ecore.EStructuralFeature
import org.eclipse.xtext.common.types.JvmOperation
import org.eclipse.xtext.common.types.JvmType
import org.eclipse.xtext.common.types.util.JavaReflectAccess
import org.eclipse.xtext.nodemodel.util.NodeModelUtils
import org.eclipse.xtext.validation.Check
import org.eclipse.xtext.xbase.XAbstractFeatureCall
import org.eclipse.xtext.xbase.XBooleanLiteral
import org.eclipse.xtext.xbase.XConstructorCall
import org.eclipse.xtext.xbase.XExpression
import org.eclipse.xtext.xbase.XFeatureCall
import org.eclipse.xtext.xbase.XNumberLiteral
import org.eclipse.xtext.xbase.XbasePackage
import org.eclipse.xtext.xbase.jvmmodel.IJvmModelAssociations
import org.eclipse.xtext.xtype.XImportDeclaration
import org.eclipse.xtext.xtype.XtypePackage
import org.xtext.xrobot.dsl.interpreter.XRobotInterpreter
import org.xtext.xrobot.dsl.interpreter.security.RobotSecurityManager
import org.xtext.xrobot.dsl.xRobotDSL.Function
import org.xtext.xrobot.dsl.xRobotDSL.Program
import org.xtext.xrobot.dsl.xRobotDSL.Variable
import org.xtext.xrobot.dsl.xRobotDSL.XRobotDSLPackage

/**
 * Custom validation rules. 
 *
 * see http://www.eclipse.org/Xtext/documentation.html#validation
 */
class XRobotDSLValidator extends AbstractXRobotDSLValidator {
	
	@Inject extension JavaReflectAccess
	
	@Inject extension IJvmModelAssociations
	
	extension XtypePackage = XtypePackage.eINSTANCE
	
	extension XbasePackage = XbasePackage.eINSTANCE
	
	extension XRobotDSLPackage = XRobotDSLPackage.eINSTANCE
	
	@Check
	def checkProgramModes(Program program) {
		var unreachable = false
		var i = 0
		val modeNames = <String>newHashSet()
		for (mode : program.modes) {
			if (unreachable || mode.condition instanceof XBooleanLiteral
					&& !(mode.condition as XBooleanLiteral).isTrue) {
				error('The mode ' + mode.name + ' is never executed',
					program, program_Modes, i)
			} else if (mode.condition == null || mode.condition instanceof XBooleanLiteral
					&& (mode.condition as XBooleanLiteral).isTrue) {
				unreachable = true
			}
			if (modeNames.contains(mode.name)) {
				warning('Duplicate mode name',
					mode, mode_Name)
			} else {
				modeNames.add(mode.name)
			}
			i++
		}
	}
	
	@Check
	def checkImportAllowed(XImportDeclaration declaration) {
		val pkg = declaration.importedType?.packageName
		if (pkg != null && !RobotSecurityManager.ALLOWED_PACKAGES.contains(pkg)) {
			error('Access to package ' + pkg + ' is not allowed',
				declaration, XImportDeclaration_ImportedType)
		}
	}
	
	@Check
	def checkConstructorCallAllowed(XConstructorCall call) {
		call.constructor?.declaringType?.checkTypeReferenceAllowed(call,
				XConstructorCall_Constructor)
	}
	
	@Check
	def checkFeatureCallAllowed(XAbstractFeatureCall call) {
		if (call.feature instanceof JvmOperation) {
			val operation = call.feature as JvmOperation
			operation.declaringType?.checkTypeReferenceAllowed(call,
					XAbstractFeatureCall_Feature)
			operation.checkMethodReferenceAllowed(call.actualArguments, call,
					XAbstractFeatureCall_Feature)
		}
	}
	
	@Check 
	def checkScriptTooLong(Program program) {
		val documentLength = NodeModelUtils.findActualNodeFor(program).rootNode.totalLength
		if(documentLength > 65536) {
			error('Script exceeds limit of 64k characters', program, null)			
		} 
	}
	
	private def checkTypeReferenceAllowed(JvmType type, EObject source, EStructuralFeature feature) {
		val clazz = type.rawType
		if (clazz != null) {
			val pkg = clazz.package.name
			if (pkg != null && !RobotSecurityManager.ALLOWED_PACKAGES.contains(pkg)) {
				error('Access to package ' + pkg + ' is not allowed',
					source, feature)
			} else if (RobotSecurityManager.RESTRICTED_CLASSES.exists[isAssignableFrom(clazz)]) {
				error('Use of class ' + clazz.simpleName + ' is not allowed',
					source, feature)
			}
		}
	}
	
	private def checkMethodReferenceAllowed(JvmOperation operation, List<XExpression> arguments,
			EObject source, EStructuralFeature feature) {
		val clazz = operation.declaringType?.rawType
		if (clazz != null) {
			if (clazz == InputOutput) {
				warning('You will not see the output of this statement',
					source, feature)
			} else if (clazz == ArrayLiterals) {
				val arg = arguments.head
				if (arg instanceof XNumberLiteral) {
					try {
						val size = Integer.parseInt((arg as XNumberLiteral).value)
						if (size > XRobotInterpreter.MAX_ARRAY_SIZE) {
							warning('The maximal allowed array size is ' + XRobotInterpreter.MAX_ARRAY_SIZE,
								arg, XNumberLiteral_Value)
						}
					} catch (NumberFormatException e) {
						// Ignore exception
					}
				}
			} else if (clazz == Object) {
				if (operation.simpleName == 'wait') {
					error('Object synchronization methods are not allowed (use sleep(int) to delay execution)',
						source, feature)
				}
			}
		}
	}
	
	@Check 
	def checkDefsUsed(Program program) {
		val usedVariables = <Variable>newHashSet
		val usedFunctions = <Function>newHashSet
		program.eAllContents.filter(typeof(XFeatureCall)).forEach[ featureCall |
			val sourceElem = featureCall.feature?.sourceElements?.head
			if (sourceElem instanceof Variable) {
				usedVariables += sourceElem
			} else if (sourceElem instanceof Function) {
				usedFunctions += sourceElem
			}
		]
		
		program.variables.forEach[ variable, i |
			if (!usedVariables.contains(variable)) {
				warning('The value of the global variable ' + variable.name + ' is not used',
					program, program_Variables, i)
			}
		]
		
		program.functions.forEach[ function, i |
			if (!usedFunctions.contains(function)) {
				warning('The function ' + function.name + ' is not used',
					program, program_Functions, i)
			}
		]
	}
	
}
