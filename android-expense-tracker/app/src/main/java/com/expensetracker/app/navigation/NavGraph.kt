package com.expensetracker.app.navigation

import androidx.compose.runtime.Composable
import androidx.navigation.NavType
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.rememberNavController
import androidx.navigation.navArgument
import com.expensetracker.app.ui.ExpenseViewModel
import com.expensetracker.app.ui.screens.AddEditExpenseScreen
import com.expensetracker.app.ui.screens.ExpenseListScreen

private const val ROUTE_LIST = "list"
private const val ROUTE_ADD = "add"
private const val ROUTE_EDIT = "edit/{expenseId}"

@Composable
fun ExpenseNavGraph(viewModel: ExpenseViewModel) {
    val navController = rememberNavController()

    NavHost(navController = navController, startDestination = ROUTE_LIST) {
        composable(ROUTE_LIST) {
            ExpenseListScreen(
                viewModel = viewModel,
                onAddExpense = { navController.navigate(ROUTE_ADD) },
                onEditExpense = { id -> navController.navigate("edit/$id") },
            )
        }
        composable(ROUTE_ADD) {
            AddEditExpenseScreen(
                viewModel = viewModel,
                expenseId = null,
                onDone = { navController.popBackStack() },
            )
        }
        composable(
            route = ROUTE_EDIT,
            arguments = listOf(navArgument("expenseId") { type = NavType.LongType }),
        ) { backStackEntry ->
            val expenseId = backStackEntry.arguments?.getLong("expenseId")
            AddEditExpenseScreen(
                viewModel = viewModel,
                expenseId = expenseId,
                onDone = { navController.popBackStack() },
            )
        }
    }
}
