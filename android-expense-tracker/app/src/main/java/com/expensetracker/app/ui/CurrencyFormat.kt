package com.expensetracker.app.ui

import java.text.NumberFormat
import java.util.Locale

fun formatCurrency(amount: Double): String =
    NumberFormat.getCurrencyInstance(Locale.getDefault()).format(amount)
