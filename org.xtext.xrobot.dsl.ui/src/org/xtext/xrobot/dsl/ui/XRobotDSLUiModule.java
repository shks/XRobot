/*
 * generated by Xtext
 */
package org.xtext.xrobot.dsl.ui;

import org.eclipse.ui.plugin.AbstractUIPlugin;
import org.eclipse.xtext.ui.editor.contentassist.IContentProposalPriorities;
import org.eclipse.xtext.ui.editor.contentassist.ITemplateProposalProvider;
import org.xtext.xrobot.dsl.ui.contentassist.XRobotContentProposalPriorities;
import org.xtext.xrobot.dsl.ui.contentassist.XRobotTemplateProposalProvider;

/**
 * Use this class to register components to be used within the IDE.
 */
public class XRobotDSLUiModule extends org.xtext.xrobot.dsl.ui.AbstractXRobotDSLUiModule {
	public XRobotDSLUiModule(AbstractUIPlugin plugin) {
		super(plugin);
	}
	
	public Class<? extends IContentProposalPriorities> bindIContentProposalPriorities() {
		return XRobotContentProposalPriorities.class;
	}
	
	public Class<? extends ITemplateProposalProvider> bindITemplateProposalProvider() {
		return XRobotTemplateProposalProvider.class;
	}
}
