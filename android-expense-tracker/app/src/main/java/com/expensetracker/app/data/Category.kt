package com.expensetracker.app.data

import androidx.compose.ui.graphics.Color

enum class Category(val label: String, val emoji: String, val color: Color) {
    FOOD("Food", "🍔", Color(0xFFEF6C00)),
    TRANSPORT("Transport", "🚗", Color(0xFF1565C0)),
    SHOPPING("Shopping", "🛒", Color(0xFF8E24AA)),
    BILLS("Bills", "🧾", Color(0xFFC62828)),
    ENTERTAINMENT("Entertainment", "🎬", Color(0xFF00838F)),
    HEALTH("Health", "🏥", Color(0xFF2E7D32)),
    EDUCATION("Education", "📚", Color(0xFF5D4037)),
    OTHER("Other", "📌", Color(0xFF616161)),
}
