package br.com.log20.variavel

import dev.hotwire.core.turbo.visit.VisitProposal
import dev.hotwire.core.turbo.webview.HotwireWebView
import dev.hotwire.navigation.activities.HotwireActivity
import dev.hotwire.navigation.destinations.HotwireDestinationDeepLink
import dev.hotwire.navigation.fragments.HotwireWebFragment
import dev.hotwire.navigation.navigator.NavigatorConfiguration
import dev.hotwire.navigation.routing.Router

class PdfRouteDecisionHandler : Router.RouteDecisionHandler {
    override val name = "pdf-reader"

    override fun matches(proposal: VisitProposal, configuration: NavigatorConfiguration) =
        PdfDownload.isPdf(proposal.location) &&
            PdfDownload.sameOrigin(configuration.startLocation, proposal.location)

    override fun handle(proposal: VisitProposal, configuration: NavigatorConfiguration,
                        activity: HotwireActivity): Router.Decision {
        PdfActivity.open(activity, proposal.location)
        return Router.Decision.CANCEL
    }
}

class DownloadRouteDecisionHandler : Router.RouteDecisionHandler {
    override val name = "file-download"
    override fun matches(proposal: VisitProposal, configuration: NavigatorConfiguration) =
        PdfDownload.sameOrigin(configuration.startLocation, proposal.location) &&
            DownloadRoutes.matches(proposal.location)

    override fun handle(proposal: VisitProposal, configuration: NavigatorConfiguration,
                        activity: HotwireActivity): Router.Decision {
        DownloadActivity.open(activity, proposal.location)
        return Router.Decision.CANCEL
    }
}

@HotwireDestinationDeepLink(uri = "hotwire://fragment/web")
class VariavelWebFragment : HotwireWebFragment() {
    private val pushRegistration = PushRegistration(this)

    override fun onVisitCompleted(location: String, completedOffline: Boolean) {
        super.onVisitCompleted(location, completedOffline)
        if (!completedOffline) pushRegistration.sync(navigator.session.webView)
    }

    override fun onResume() {
        super.onResume()
        pushRegistration.sync(navigator.session.webView)
    }
    // The Rails navbar already supplies the title and menus for each user's role.
    override fun onCreateView(
        inflater: android.view.LayoutInflater,
        container: android.view.ViewGroup?,
        savedInstanceState: android.os.Bundle?
    ): android.view.View = inflater.inflate(dev.hotwire.navigation.R.layout.hotwire_view, container, false)

    override fun createErrorView(error: dev.hotwire.core.turbo.errors.VisitError): android.view.View {
        return android.widget.LinearLayout(requireContext()).apply {
            orientation = android.widget.LinearLayout.VERTICAL
            gravity = android.view.Gravity.CENTER
            addView(android.widget.TextView(context).apply { setText(R.string.hotwire_error_message) })
            addView(android.widget.TextView(context).apply { setText(R.string.connection_retry) })
            addView(android.widget.Button(context).apply {
                setText(R.string.retry)
                setOnClickListener { refresh() }
            })
        }
    }
    override fun onWebViewAttached(webView: HotwireWebView) {
        super.onWebViewAttached(webView)
        // Handles PDFs identified by response MIME type, including attachment URLs.
        webView.setDownloadListener { url, _, _, mimeType, _ ->
            if (mimeType?.substringBefore(';')?.trim().equals("application/pdf", true) || PdfDownload.isPdf(url)) {
                PdfActivity.open(requireActivity(), url)
            } else {
                DownloadActivity.open(requireActivity(), url)
            }
        }
    }
}
