package com.explorechiayi.tdx_server.config;

import io.github.cdimascio.dotenv.Dotenv;
import org.springframework.context.annotation.Configuration;

@Configuration
public class TdxConfig {
    // 自動載入根目錄的 .env 檔案
    private static final Dotenv dotenv = Dotenv.configure().ignoreIfMissing().load();

    public static final String CLIENT_ID = dotenv.get("TDX_CLIENT_ID");
    public static final String CLIENT_SECRET = dotenv.get("TDX_CLIENT_SECRET");
    public static final String CWA_API_KEY = dotenv.get("CWA_API_KEY");
}