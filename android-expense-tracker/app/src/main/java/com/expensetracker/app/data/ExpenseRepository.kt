package com.expensetracker.app.data

import kotlinx.coroutines.flow.Flow

class ExpenseRepository(private val dao: ExpenseDao) {

    fun getExpensesBetween(startMillis: Long, endMillis: Long): Flow<List<Expense>> =
        dao.getExpensesBetween(startMillis, endMillis)

    suspend fun getById(id: Long): Expense? = dao.getById(id)

    suspend fun save(expense: Expense): Long =
        if (expense.id == 0L) dao.insert(expense) else { dao.update(expense); expense.id }

    suspend fun delete(expense: Expense) = dao.delete(expense)
}
