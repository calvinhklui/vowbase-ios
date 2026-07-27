import Foundation
protocol BudgetRepository:Sendable{func budgetItems(weddingID:UUID)async throws->[BudgetItem];func createBudgetItem(_ draft:BudgetItemDraft,weddingID:UUID)async throws->BudgetItem;func updateBudgetItem(id:UUID,patch:BudgetItemPatch)async throws->BudgetItem;func deleteBudgetItem(id:UUID)async throws}
