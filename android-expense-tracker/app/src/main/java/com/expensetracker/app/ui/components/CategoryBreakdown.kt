package com.expensetracker.app.ui.components

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.unit.dp
import com.expensetracker.app.data.Category
import com.expensetracker.app.ui.formatCurrency

@Composable
fun CategoryBreakdown(
    totals: List<Pair<Category, Double>>,
    grandTotal: Double,
    modifier: Modifier = Modifier,
) {
    Column(modifier = modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        totals.forEach { (category, amount) ->
            val fraction = if (grandTotal > 0) (amount / grandTotal).toFloat() else 0f
            Column(modifier = Modifier.padding(vertical = 2.dp)) {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                ) {
                    Text("${category.emoji} ${category.label}", style = MaterialTheme.typography.bodyMedium)
                    Text(formatCurrency(amount), style = MaterialTheme.typography.bodyMedium)
                }
                LinearProgressIndicator(
                    progress = { fraction },
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(top = 4.dp)
                        .clip(RoundedCornerShape(4.dp)),
                    color = category.color,
                )
            }
        }
    }
}
