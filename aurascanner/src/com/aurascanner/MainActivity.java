package com.aurascanner;

import android.app.Activity;
import android.os.Bundle;
import android.webkit.PermissionRequest;
import android.webkit.WebChromeClient;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;

import com.aurascanner.AssetLoader;

public class MainActivity extends Activity {

    private WebView webView;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_main);

        webView = findViewById(R.id.webview);
        WebSettings ws = webView.getSettings();
        ws.setJavaScriptEnabled(true);
        ws.setDomStorageEnabled(true);
        ws.setMediaPlaybackRequiresUserGesture(false);
        ws.setAllowFileAccess(true);
        ws.setAllowContentAccess(true);

        webView.setWebViewClient(new WebViewClient());
        webView.setWebChromeClient(new WebChromeClient() {
            @Override
            public void onPermissionRequest(final PermissionRequest request) {
                runOnUiThread(new Runnable() {
                    @Override
                    public void run() {
                        for (String resource : request.getResources()) {
                            if (resource.equals(PermissionRequest.RESOURCE_VIDEO_CAPTURE)) {
                                request.grant(resources);
                                return;
                            }
                        }
                        request.deny();
                    }
                });
            }
        });

        // Hydrate assets/ → filesDir (so WebView can file:// load + service worker can register)
        AssetLoader.copyAssetsToFiles(getAssets(), getFilesDir());

        // Load local PWA from sandboxed file:// URI
        webView.loadUrl("file://" + getFilesDir() + "/www/index.html");
    }

    @Override
    public void onBackPressed() {
        if (webView != null && webView.canGoBack()) {
            webView.goBack();
        } else {
            super.onBackPressed();
        }
    }

    @Override
    protected void onDestroy() {
        if (webView != null) {
            webView.destroy();
            webView = null;
        }
        super.onDestroy();
    }
}
