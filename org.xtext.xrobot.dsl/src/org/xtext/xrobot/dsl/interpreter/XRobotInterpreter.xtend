/*******************************************************************************
 * Copyright (c) 2014 itemis AG (http://www.itemis.eu) and others.
 * All rights reserved. This program and the accompanying materials
 * are made available under the terms of the Eclipse Public License v1.0
 * which accompanies this distribution, and is available at
 * http://www.eclipse.org/legal/epl-v10.html
 *
 *******************************************************************************/
package org.xtext.xrobot.dsl.interpreter

import com.google.inject.Inject
import java.lang.reflect.Constructor
import java.lang.reflect.Field
import java.lang.reflect.Method
import java.util.HashMap
import java.util.List
import org.apache.log4j.Logger
import org.eclipse.xtend.lib.annotations.Accessors
import org.eclipse.xtext.common.types.JvmDeclaredType
import org.eclipse.xtext.common.types.JvmField
import org.eclipse.xtext.common.types.JvmIdentifiableElement
import org.eclipse.xtext.common.types.JvmOperation
import org.eclipse.xtext.common.types.util.JavaReflectAccess
import org.eclipse.xtext.naming.QualifiedName
import org.eclipse.xtext.nodemodel.util.NodeModelUtils
import org.eclipse.xtext.util.CancelIndicator
import org.eclipse.xtext.xbase.XAbstractFeatureCall
import org.eclipse.xtext.xbase.XConstructorCall
import org.eclipse.xtext.xbase.XExpression
import org.eclipse.xtext.xbase.interpreter.IEvaluationContext
import org.eclipse.xtext.xbase.interpreter.impl.EvaluationException
import org.eclipse.xtext.xbase.interpreter.impl.XbaseInterpreter
import org.eclipse.xtext.xbase.jvmmodel.IJvmModelAssociations
import org.xtext.xrobot.api.IRobot
import org.xtext.xrobot.dsl.interpreter.security.RobotSecurityManager
import org.xtext.xrobot.dsl.xRobotDSL.Function
import org.xtext.xrobot.dsl.xRobotDSL.Mode
import org.xtext.xrobot.dsl.xRobotDSL.Program
import org.xtext.xrobot.dsl.xRobotDSL.Variable
import org.xtext.xrobot.server.CanceledException
import org.xtext.xrobot.server.IRemoteRobot
import org.xtext.xrobot.util.AudioService

import static org.xtext.xrobot.dsl.interpreter.XRobotInterpreter.*

class XRobotInterpreter extends XbaseInterpreter {

	/** Limit on the recursion depth of functions. */
	public static val RECURSION_LIMIT = 100
	/** Limit on the number of elements in allocated arrays. */
	public static val MAX_ARRAY_SIZE = 5000
	
	/** Thread class used for executing robots. */
	static class RobotThread extends Thread {
		new(ThreadGroup group, String name) {
			super(group, name)
		}
	}
	
	static val LOG = Logger.getLogger(XRobotInterpreter)
	
	static val ROBOT_UPDATE_TIMEOUT = 2000
	static val long MIN_FREE_MEMORY = 64 * 1024 * 1024
	
	static val ROBOT = QualifiedName.create('Dummy')
	static val CURRENT_LINE = QualifiedName.create('currentLine')

	@Inject extension IJvmModelAssociations
	
	@Inject JavaReflectAccess javaReflectAccess
	
	@Accessors
	boolean trackLineChanges
	
	IEvaluationContext baseContext

	List<IRobotListener> listeners
	
	Throwable lastModeException
	
	val recursionCounter = new HashMap<JvmOperation, Integer>
	
	def void execute(Program program, IRemoteRobot.Factory robotFactory, List<IRobotListener> listeners, CancelIndicator cancelIndicator) {
		var InternalCancelIndicator currentModeCancelIndicator
		try {
			this.listeners = listeners
			// Reset the audio call counters of the audio service
			AudioService.getInstance.resetCounters
			// Start the security manager in order to block all illegal operations
			RobotSecurityManager.start
			
			val conditionCancelIndicator = new InternalCancelIndicator(cancelIndicator)
			val conditionRobot = robotFactory.newRobot(conditionCancelIndicator)
			conditionRobot.reset
			baseContext = createContext
			baseContext.newValue(ROBOT, conditionRobot)
			val conditionContext = baseContext.fork()
			
			// Initialize program fields
			for (variable : program.variables) {
				if (variable.initializer != null) {
					val initialValue = variable.initializer.evaluateChecked(baseContext, cancelIndicator)
					baseContext.newValue(QualifiedName.create(variable.name), initialValue)
				} else {
					baseContext.newValue(QualifiedName.create(variable.name), null)
				}
			}
			
			var Mode currentMode
			var IEvaluationContext currentModeContext
			do {
				listeners.forEach[stateRead(conditionRobot)]
				if(!conditionCancelIndicator.isCanceled) {
					val newMode = program.modes.findFirst [
						if(condition == null)
							return true
						val result = condition.evaluateChecked(conditionContext, conditionCancelIndicator)
						return result as Boolean ?: false
					]
					val oldMode = currentMode
					if (newMode != oldMode
							|| currentModeCancelIndicator != null && currentModeCancelIndicator.isCanceled) {
						currentModeCancelIndicator?.cancel
						if (newMode != null) {
							
							// Start a new thread executing the activated mode
							val oldModeContext = currentModeContext
							val modeCancelIndicator = new InternalCancelIndicator(cancelIndicator)
							val modeRobot = robotFactory.newRobot(modeCancelIndicator, conditionRobot)
							val newModeContext = baseContext.fork
							newModeContext.newValue(ROBOT, modeRobot)
							if (trackLineChanges) {
								val modeNode = NodeModelUtils.findActualNodeFor(newMode)
								if (modeNode != null) {
									newModeContext.newValue(CURRENT_LINE, modeNode.startLine)
								}
							}
							val thread = new RobotThread(Thread.currentThread.threadGroup,
									'Robot ' + modeRobot.robotID.name + ' in mode ' + newMode.name) {
								override run() {
									try {
										RobotSecurityManager.start
										// First execute the 'when left' block of the old mode
										if (oldMode != null && newMode != oldMode
												&& oldMode.whenLeft != null) {
											LOG.debug('Executing when-left code of mode ' + oldMode.name)
											val robot = oldModeContext.getValue(ROBOT) as IRemoteRobot
											val context = baseContext.fork
											context.newValue(ROBOT, robotFactory.newRobot(cancelIndicator, robot))
											oldMode.whenLeft.evaluateChecked(context, cancelIndicator)
										}
										// Then execute the main block of the new mode
										LOG.debug('Starting mode ' +  newMode.name)
										newMode.execute(newModeContext, modeCancelIndicator)
									} catch (CanceledException ce) {
										// Mode execution was canceled - ignore the exception
									} catch (Throwable thr) {
										LOG.error('Error executing mode ' + newMode.name
											+ " (" + thr.class.simpleName + ")")
										lastModeException = thr
										conditionCancelIndicator.cancel
									} finally {
										modeCancelIndicator.cancel
										RobotSecurityManager.stop
									}
								}
							}
							currentMode = newMode
							currentModeContext = newModeContext
							currentModeCancelIndicator = modeCancelIndicator
							thread.start
							
						}
					}
					Thread.yield
					conditionRobot.waitForUpdate(ROBOT_UPDATE_TIMEOUT)
					if(newMode == null)
						listeners.forEach[ stateChanged(conditionRobot) ]
				}
			} while(!conditionCancelIndicator.isCanceled)
			
			if (lastModeException != null) {
				throw lastModeException
			}
		} catch (CanceledException exc) {
			if (lastModeException != null) {
				throw lastModeException
			}
		} finally {
			currentModeCancelIndicator?.cancel
			RobotSecurityManager.stop
		}
	}
	
	protected def execute(Mode mode, IEvaluationContext context, CancelIndicator cancelIndicator) {
		listeners.forEach[
			val robot = context.getValue(ROBOT) as IRemoteRobot
			modeChanged(robot, mode)
			stateChanged(robot)
		]
		mode.action.evaluateChecked(context, cancelIndicator)
	}
	
	private def evaluateChecked(XExpression expression, IEvaluationContext context, CancelIndicator indicator) {
		try {
			val result = super.evaluate(expression, context, indicator)
			if (result?.exception != null) {
				throw result.exception
			}
			return result?.result
		} catch (ExceptionInInitializerError error) {
			throw error.cause
		} catch (OutOfMemoryError err) {
			throw new MemoryException("Heap memory limit exceeded", err)
		}
	}
	
	static class InternalCancelIndicator implements CancelIndicator {
		
		CancelIndicator baseCancelindicator
		boolean canceled
		
		new(CancelIndicator baseCancelindicator) {
			this.baseCancelindicator = baseCancelindicator
		}
		
		def void cancel() {
			canceled = true
		}
		
		override isCanceled() {
			canceled || baseCancelindicator.canceled 
		}
	}
	
	private def getAvailableMemory() {
		val runtime = Runtime.runtime
		runtime.maxMemory() - runtime.totalMemory() + runtime.freeMemory()
	}
	
	override protected internalEvaluate(XExpression expression, IEvaluationContext context, CancelIndicator indicator) throws EvaluationException {
		if (indicator.isCanceled) 
			throw new CanceledException()
		if (trackLineChanges) {
			val node = NodeModelUtils.findActualNodeFor(expression)
			if (node != null) {
				val startLine = node.startLine
				val lastLine = context.getValue(CURRENT_LINE)
				if (!(lastLine instanceof Integer) || (lastLine as Integer).intValue != startLine) {
					context.assignValue(CURRENT_LINE, startLine)
					listeners.forEach[lineChanged(startLine)]
				}
			}
		}
		
		// Check current memory status
		if (availableMemory < MIN_FREE_MEMORY) {
			LOG.info("Program is about to exceed heap memory limit.")
			Runtime.runtime.gc
			if (availableMemory < MIN_FREE_MEMORY) {
				// Garbage collection did not help, so abort program execution
				throw new MemoryException("Heap memory limit exceeded")
			}
		}
		
		super.internalEvaluate(expression, context, indicator)
	}
	
	private def increaseRecursion(JvmOperation operation) {
		synchronized (recursionCounter) {
			val c = recursionCounter.get(operation) ?: 0
			if (c > RECURSION_LIMIT) {
				throw new MemoryException("Recursion limit exceeded by '" + operation.simpleName + "'")
			}
			recursionCounter.put(operation, c + 1)
		}
	}
	
	private def decreaseRecursion(JvmOperation operation) {
		synchronized (recursionCounter) {
			val c = recursionCounter.get(operation)
			if (c == null || c == 0) {
				throw new IllegalStateException
			}
			recursionCounter.put(operation, c - 1)
		}
	}
	
	override protected invokeOperation(JvmOperation operation, Object receiver, List<Object> argumentValues, IEvaluationContext context, CancelIndicator indicator) {
		val executable = operation.sourceElements.head
		if (executable instanceof Function) {
			val newContext = baseContext.fork
			newContext.newValue(ROBOT, context.getValue(ROBOT))
			var index = 0
			for (param : operation.parameters) {
				newContext.newValue(QualifiedName.create(param.name), argumentValues.get(index))
				index = index + 1	
			}
			operation.increaseRecursion
			try {
				return evaluateChecked(executable.body, newContext, indicator)
			} finally {
				operation.decreaseRecursion
			}
		} else {
			val receiverDeclaredType = javaReflectAccess.getRawType(operation.declaringType)
			if (receiverDeclaredType == IRobot) {
				super.invokeOperation(operation, receiver, argumentValues)
			} else if (receiverDeclaredType == ArrayLiterals) {
				val size = argumentValues.head as Integer ?: 0
				if (size > MAX_ARRAY_SIZE) {
					throw new MemoryException("Size limit exceeded by array")
				}
				super.invokeOperation(operation, receiver, argumentValues)
			} else if (receiverDeclaredType == Object && operation.simpleName == 'wait') {
				LOG.info("Blocked invocation of Object#wait().")
				return null
			} else if (receiverDeclaredType == Method || receiverDeclaredType == Constructor
					|| receiverDeclaredType == Field) {
				throw new SecurityException("Reflection is not allowed.")
			} else {
				operation.increaseRecursion
				// Make sure our security manager is active while invoking the method
				val token = RobotSecurityManager.activate
				try {
					System.securityManager.checkPackageAccess(operation.declaringType.packageName)
					return super.invokeOperation(operation, receiver, argumentValues)
				} finally {
					RobotSecurityManager.deactivate(token)
					operation.decreaseRecursion
				}
			}
		}
	}
	
	override protected _doEvaluate(XConstructorCall constructorCall, IEvaluationContext context, CancelIndicator indicator) {
		// Make sure our security manager is active while invoking the constructor
		val token = RobotSecurityManager.activate
		try {
			System.securityManager.checkPackageAccess(constructorCall.constructor.declaringType.packageName)
			super._doEvaluate(constructorCall, context, indicator)
		} finally {
			RobotSecurityManager.deactivate(token)
		}
	}
	
	override protected featureCallField(JvmField jvmField, Object receiver) {
		val variable = jvmField.sourceElements.head
		if (variable instanceof Variable) 
			baseContext.getValue(QualifiedName.create(variable.name))
		else
			super.featureCallField(jvmField, receiver)
	}

	override protected _assignValueTo(JvmField jvmField, XAbstractFeatureCall assignment, Object value, IEvaluationContext context, CancelIndicator indicator) {
		val variable = jvmField.sourceElements.head
		if (variable instanceof Variable) {
			context.assignValue(QualifiedName.create(variable.name), value)
			listeners.forEach[variableChanged(variable.name, value)]
		} else {
			super._assignValueTo(jvmField, assignment, value, context, indicator)
		}
		value 
	}
	
	override Object _invokeFeature(JvmIdentifiableElement identifiable, XAbstractFeatureCall featureCall, Object receiver,
			IEvaluationContext context, CancelIndicator indicator) {
		if(identifiable instanceof JvmDeclaredType) 
			return context.getValue(ROBOT)
		else 
			return super._invokeFeature(identifiable, featureCall, receiver, context, indicator)
			
	}
}