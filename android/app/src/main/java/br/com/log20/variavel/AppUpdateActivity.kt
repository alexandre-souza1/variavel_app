package br.com.log20.variavel

import android.content.ClipData
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.provider.Settings
import android.view.View
import android.widget.Button
import android.widget.LinearLayout
import android.widget.ProgressBar
import android.widget.ScrollView
import android.widget.TextView
import androidx.activity.enableEdgeToEdge
import androidx.activity.result.contract.ActivityResultContracts
import androidx.appcompat.app.AppCompatActivity
import androidx.core.content.FileProvider
import androidx.core.view.ViewCompat
import androidx.core.view.WindowInsetsCompat
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.lifecycleScope
import androidx.lifecycle.repeatOnLifecycle
import kotlinx.coroutines.launch

class AppUpdateActivity : AppCompatActivity() {
    private lateinit var model: AppUpdateViewModel
    private lateinit var status: TextView
    private lateinit var notes: TextView
    private lateinit var action: Button
    private lateinit var progress: ProgressBar
    private val install = registerForActivityResult(ActivityResultContracts.StartActivityForResult()) {
        // A cancelled installer leaves the verified APK available for another attempt.
        action.isEnabled = true
    }
    private val permission = registerForActivityResult(ActivityResultContracts.StartActivityForResult()) {
        if (packageManager.canRequestPackageInstalls()) installReadyUpdate()
        else status.setText(R.string.update_permission_needed)
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        enableEdgeToEdge()
        super.onCreate(savedInstanceState)
        model = ViewModelProvider(this)[AppUpdateViewModel::class.java]
        val root = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL }
        val padding = (20 * resources.displayMetrics.density).toInt()
        ViewCompat.setOnApplyWindowInsetsListener(root) { view, insets ->
            val bars = insets.getInsets(WindowInsetsCompat.Type.systemBars() or WindowInsetsCompat.Type.displayCutout())
            view.setPadding(bars.left + padding, bars.top + padding, bars.right + padding, bars.bottom + padding)
            insets
        }
        root.addView(Button(this).apply { setText(R.string.back); setOnClickListener { finish() } })
        root.addView(TextView(this).apply { setText(R.string.update_title); textSize = 24f })
        root.addView(TextView(this).apply {
            text = getString(R.string.update_installed_version, BuildConfig.VERSION_NAME)
        })
        status = TextView(this).apply { textSize = 18f }
        notes = TextView(this)
        progress = ProgressBar(this, null, android.R.attr.progressBarStyleHorizontal).apply { max = 100 }
        action = Button(this)
        root.addView(status); root.addView(notes); root.addView(progress); root.addView(action)
        setContentView(ScrollView(this).apply { addView(root) })
        lifecycleScope.launch {
            repeatOnLifecycle(Lifecycle.State.STARTED) { model.state.collect { render(it) } }
        }
    }

    private fun render(state: AppUpdateState) {
        action.visibility = View.GONE
        action.isEnabled = true
        progress.visibility = View.GONE
        notes.text = when (state) {
            is AppUpdateState.Available -> state.update.notes
            is AppUpdateState.Downloading -> state.update.notes
            is AppUpdateState.Ready -> state.update.notes
            else -> ""
        }
        when (state) {
            AppUpdateState.Checking -> status.setText(R.string.update_checking)
            AppUpdateState.Current -> status.setText(R.string.update_current)
            is AppUpdateState.Available -> {
                status.text = getString(R.string.update_available, state.update.versionName)
                showAction(R.string.update_download) { model.download() }
            }
            is AppUpdateState.Downloading -> {
                status.text = getString(R.string.update_downloading, state.percent)
                progress.visibility = View.VISIBLE
                progress.progress = state.percent
            }
            is AppUpdateState.Ready -> {
                status.setText(R.string.update_ready)
                showAction(R.string.update_install) { installReadyUpdate() }
            }
            is AppUpdateState.Failed -> {
                status.text = state.message
                showAction(R.string.retry) { model.check() }
            }
        }
    }

    private fun showAction(label: Int, clicked: () -> Unit) {
        action.visibility = View.VISIBLE
        action.setText(label)
        action.setOnClickListener { clicked() }
    }

    private fun installReadyUpdate() {
        val ready = model.state.value as? AppUpdateState.Ready ?: return
        try {
            if (!packageManager.canRequestPackageInstalls()) {
                status.setText(R.string.update_permission_needed)
                permission.launch(Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:$packageName")))
                return
            }
            if (!ready.file.exists()) {
                model.check()
                return
            }
            val uri = FileProvider.getUriForFile(this, "$packageName.exports", ready.file)
            install.launch(Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(uri, "application/vnd.android.package-archive")
                clipData = ClipData.newUri(contentResolver, "Logia", uri)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            })
        } catch (_: Exception) {
            status.setText(R.string.update_install_failed)
            action.isEnabled = true
        }
    }

    companion object {
        fun open(context: Context) = context.startActivity(Intent(context, AppUpdateActivity::class.java))
    }
}
