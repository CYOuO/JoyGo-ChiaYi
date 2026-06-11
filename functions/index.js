/**
 * JoyGo 嘉義 — Firebase Cloud Functions
 * 功能：監聽 Firestore broadcasts 集合，自動發送 FCM 推播給所有使用者
 *
 * 部署指令：firebase deploy --only functions
 */

const { onDocumentCreated } = require("firebase-functions/v2/firestore");
const { initializeApp }     = require("firebase-admin/app");
const { getMessaging }      = require("firebase-admin/messaging");
const { getFirestore }      = require("firebase-admin/firestore");

initializeApp();

// ─────────────────────────────────────────────────────────────────────────────
// sendBroadcastNotification
//
// 觸發條件：Firestore broadcasts/{broadcastId} 文件被建立
// 文件格式：
//   {
//     title:     string,   // 通知標題（必填）
//     body:      string,   // 通知內文（必填）
//     data:      object,   // 附加資料（選填），例如 { type: 'news', id: '...' }
//     sentBy:    string,   // 發送者 uid（選填）
//     createdAt: Timestamp // 由管理員 App 自動寫入
//   }
// ─────────────────────────────────────────────────────────────────────────────
exports.sendBroadcastNotification = onDocumentCreated(
  {
    document: "broadcasts/{broadcastId}",
    region: "asia-east1",   // 選台灣最近的節點（東亞-1，新加坡）
  },
  async (event) => {
    const snap = event.data;
    if (!snap) {
      console.log("No data in event, skipping.");
      return;
    }

    const data      = snap.data();
    const title     = data.title    || "探索諸羅";
    const body      = data.body     || "";
    const extraData = data.data     || {};
    const docId     = event.params.broadcastId;

    // 防止重複發送：若文件已有 fcmSent: true 則跳過
    if (data.fcmSent === true) {
      console.log(`Broadcast ${docId} already sent, skipping.`);
      return;
    }

    console.log(`Sending broadcast [${docId}]: "${title}"`);

    try {
      // 發送到 topic 'all'（所有訂閱用戶）
      const message = {
        topic: "all",
        notification: {
          title,
          body,
        },
        data: {
          ...extraData,
          broadcastId: docId,
          clickAction: "FLUTTER_NOTIFICATION_CLICK",
        },
        android: {
          priority: "high",
          notification: {
            channelId: "joygo_high",  // 對應 Flutter 端的頻道 id
            sound: "default",
          },
        },
        apns: {
          payload: {
            aps: {
              sound: "default",
              badge: 1,
            },
          },
        },
      };

      const response = await getMessaging().send(message);
      console.log(`FCM sent successfully. messageId: ${response}`);

      // 回寫狀態，避免重複發送
      await getFirestore()
        .collection("broadcasts")
        .doc(docId)
        .update({
          fcmSent:      true,
          fcmMessageId: response,
          fcmSentAt:    new Date(),
        });

    } catch (error) {
      console.error("Failed to send FCM:", error);

      // 記錄錯誤狀態
      await getFirestore()
        .collection("broadcasts")
        .doc(docId)
        .update({
          fcmSent:  false,
          fcmError: error.message || String(error),
        }).catch(() => {});

      throw error;  // 讓 Functions 重試
    }
  }
);
