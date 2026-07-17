import Foundation


actor KakitanganAPIClient {
    private let session: URLSession
    private let decoder = JSONDecoder()

    init(session: URLSession = .shared) {
        self.session = session
    }

    func login(accountEmail: String, password: String) async throws -> String {
        guard let url = URL(string: "https://app.kakitangan.com/api/v1/auth") else {
            throw NotifierError.authenticationFailed
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode([
            "username": accountEmail,
            "password": password,
        ])

        let response: AuthResponse = try await response(for: request, failure: .authenticationFailed)
        guard !response.token.isEmpty else {
            throw NotifierError.authenticationFailed
        }
        return response.token
    }

    func fetchLeaves(token: String, fromDate: Date, toDate: Date) async throws -> [LeaveRecord] {
        var components = URLComponents(string: "https://app.kakitangan.com/api/v1/leave/")
        components?.queryItems = [
            URLQueryItem(name: "ordering", value: "start_date"),
            URLQueryItem(name: "from_date", value: DateOnly.string(from: fromDate)),
            URLQueryItem(name: "to_date", value: DateOnly.string(from: toDate)),
        ]
        guard let url = components?.url else {
            throw NotifierError.leaveRequestFailed
        }
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Token \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw NotifierError.leaveRequestFailed
        }
        if let leaves = try? decoder.decode([LeaveRecord].self, from: data) {
            return leaves
        }
        guard let page = try? decoder.decode(LeavePage.self, from: data) else {
            throw NotifierError.leaveRequestFailed
        }
        return page.results
    }

    func fetchManagedEmployees(token: String) async throws -> [ManagedEmployee] {
        guard let url = URL(string: "https://app.kakitangan.com/api/v1/payroll/user/all_managed_employees") else {
            throw NotifierError.employeeRequestFailed
        }
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Token \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw NotifierError.employeeRequestFailed
        }
        guard let employees = try? decoder.decode([ManagedEmployee].self, from: data) else {
            throw NotifierError.employeeRequestFailed
        }
        return employees
    }

    private func response<Response: Decodable>(for request: URLRequest, failure: NotifierError) async throws -> Response {
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw failure
        }
        do {
            return try decoder.decode(Response.self, from: data)
        } catch {
            throw failure
        }
    }
}
