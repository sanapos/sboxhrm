package vn.sana.dsk;

import android.app.Activity;
import android.os.Bundle;
import android.util.Log;
import android.widget.Button;
import android.widget.LinearLayout;
import android.widget.Toast;

import org.json.JSONObject;

import sunmi.ds.DSKernel;
import sunmi.ds.SF;
import sunmi.ds.callback.IConnectionCallback;
import sunmi.ds.callback.ISendCallback;
import sunmi.ds.data.DSData.DataType;
import sunmi.ds.data.DataPacket;

public class SmokeActivity extends Activity {
  private static final String TAG = "DskSmoke";
  private DSKernel kernel;

  @Override protected void onCreate(Bundle savedInstanceState) {
    super.onCreate(savedInstanceState);
    LinearLayout root = new LinearLayout(this);
    root.setOrientation(LinearLayout.VERTICAL);
    Button b1 = new Button(this); b1.setText("TEXT");
    Button b2 = new Button(this); b2.setText("WELCOME");
    root.addView(b1); root.addView(b2);
    setContentView(root);

    kernel = DSKernel.newInstance();
    kernel.init(this, new IConnectionCallback() {
      @Override public void onDisConnect() { Log.e(TAG, "disc"); }
      @Override public void onConnected(ConnState state) {
        Log.i(TAG, "conn " + state);
        runOnUiThread(() -> Toast.makeText(SmokeActivity.this, "conn "+state, Toast.LENGTH_SHORT).show());
      }
    });

    ISendCallback cb = new ISendCallback() {
      @Override public void onSendSuccess(long taskId) { Log.i(TAG, "ok "+taskId); }
      @Override public void onSendFail(int errorId, String errorInfo) { Log.e(TAG, "fail "+errorId+" "+errorInfo); }
      @Override public void onSendProcess(long totle, long sended) {}
    };

    b1.setOnClickListener(v -> {
      try {
        JSONObject inner = new JSONObject();
        inner.put("title", "SMOKE TITLE");
        inner.put("content", "smoke content OK");
        JSONObject wrap = new JSONObject();
        wrap.put("dataModel", "TEXT");
        wrap.put("data", inner.toString());
        DataPacket p = new DataPacket.Builder(DataType.DATA)
          .recPackName(DSKernel.getDSDPackageName())
          .data(wrap.toString())
          .addCallback(cb)
          .isReport(true)
          .build();
        kernel.sendData(p);
        Toast.makeText(this, "sent TEXT", Toast.LENGTH_SHORT).show();
      } catch (Exception e) { Log.e(TAG, "text", e); }
    });
    b2.setOnClickListener(v -> {
      try {
        JSONObject json = new JSONObject();
        json.put("dataModel", "SHOW_IMG_WELCOME");
        json.put("data", "smoke");
        kernel.sendCMD(SF.DSD_PACKNAME, json.toString(), -1, cb);
        Toast.makeText(this, "sent WELCOME", Toast.LENGTH_SHORT).show();
      } catch (Exception e) { Log.e(TAG, "welcome", e); }
    });
  }
}
