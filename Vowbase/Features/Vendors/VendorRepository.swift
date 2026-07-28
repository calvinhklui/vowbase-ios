import Foundation
protocol VendorRepository:Sendable{func vendors(weddingID:UUID)async throws->[Vendor];func createVendor(_ draft:VendorDraft,weddingID:UUID)async throws->Vendor;func updateVendor(id:UUID,patch:VendorPatch)async throws->Vendor;func deleteVendor(id:UUID)async throws}
